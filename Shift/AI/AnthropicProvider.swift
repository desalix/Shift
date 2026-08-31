//
//  AnthropicProvider.swift
//  Shift
//

import Foundation

/// Talks to the Anthropic Messages API over raw HTTPS.
///
/// There is no official Anthropic SDK for Swift, so this builds the request
/// bodies directly. The user's key is read from the Keychain per request and is
/// sent to `api.anthropic.com` and nowhere else.
struct AnthropicProvider: AIProvider {
    let model: String
    var session: URLSession = .shared

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"
    private let maxToolRounds = 3

    func respond(
        to history: [AssistantMessage],
        context: AssistantContext
    ) async throws -> AssistantReply {
        guard let apiKey = KeychainStore.loadAPIKey(), !apiKey.isEmpty else {
            throw AIProviderError.missingAPIKey
        }

        let timeZone = TimeZone(identifier: context.timeZoneIdentifier) ?? .current
        var messages = history.compactMap(Self.wireMessage(from:))
        var collectedActions: [AssistantAction] = []
        var finalText = ""

        // Loop so the model can call a tool, see that the proposal was queued,
        // and then write its closing message in the same turn.
        for _ in 0 ..< maxToolRounds {
            let body = requestBody(messages: messages, context: context, apiKey: apiKey)
            let payload = try await send(body: body, apiKey: apiKey)

            let content = payload["content"] as? [[String: Any]] ?? []
            var toolResults: [[String: Any]] = []

            for block in content {
                switch block["type"] as? String {
                case "text":
                    if let text = block["text"] as? String, !text.isEmpty {
                        finalText += finalText.isEmpty ? text : "\n\n" + text
                    }
                case "tool_use":
                    guard let name = block["name"] as? String,
                          let id = block["id"] as? String
                    else { continue }
                    let input = block["input"] as? [String: Any] ?? [:]
                    let actions = AssistantTools.actions(toolName: name, input: input, timeZone: timeZone)
                    collectedActions.append(contentsOf: actions)

                    toolResults.append([
                        "type": "tool_result",
                        "tool_use_id": id,
                        "content": actions.isEmpty
                            ? "No valid change could be read from those arguments. Check the date format and required fields, then try again."
                            : "Queued \(actions.count) change(s) for the user to confirm.",
                        "is_error": actions.isEmpty,
                    ])
                default:
                    continue
                }
            }

            let stopReason = payload["stop_reason"] as? String

            // A refusal is a normal 200 response, so it has to be checked before
            // treating the content as an answer.
            if stopReason == "refusal" {
                let category = (payload["stop_details"] as? [String: Any])?["category"] as? String
                throw AIProviderError.transport(
                    category.map { String(localized: "The request was declined (\($0)).") }
                        ?? String(localized: "The request was declined.")
                )
            }

            guard stopReason == "tool_use", !toolResults.isEmpty else {
                break
            }

            messages.append(["role": "assistant", "content": content])
            messages.append(["role": "user", "content": toolResults])
        }

        let proposal = collectedActions.isEmpty ? nil : AssistantProposal(actions: collectedActions)

        if finalText.isEmpty {
            finalText = proposal == nil
                ? String(localized: "I wasn't able to work out a change from that. Could you rephrase it?")
                : String(localized: "Here's what I'd change:")
        }

        return AssistantReply(text: finalText, proposal: proposal)
    }

    // MARK: - Request construction

    private func requestBody(
        messages: [[String: Any]],
        context: AssistantContext,
        apiKey: String
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": [
                [
                    "type": "text",
                    "text": AssistantTools.systemPrompt(context: context),
                    // The prompt is rebuilt per turn but its prefix is stable,
                    // so caching it pays for itself across a conversation.
                    "cache_control": ["type": "ephemeral"],
                ]
            ],
            "tools": AssistantTools.definitions(),
            "messages": messages,
        ]

        // Haiku 4.5 predates adaptive thinking and rejects the parameter; the
        // Opus and Sonnet 5 models take it and benefit from it here, because
        // expanding a recurrence with skip rules is genuinely multi-step.
        if model != AssistantModel.haiku.rawValue {
            body["thinking"] = ["type": "adaptive"]
        }

        return body
    }

    private func send(body: [String: Any], apiKey: String) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(AnthropicFiles.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 120

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw AIProviderError.malformedResponse
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIProviderError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIProviderError.malformedResponse
        }

        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.malformedResponse
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            let message = (payload["error"] as? [String: Any])?["message"] as? String ?? ""
            throw AIProviderError.http(status: http.statusCode, message: Self.friendlyMessage(status: http.statusCode, apiMessage: message))
        }

        return payload
    }

    /// Turns the common failures into something a user can act on.
    private static func friendlyMessage(status: Int, apiMessage: String) -> String {
        switch status {
        case 401:
            return String(localized: "That API key was rejected. Check it in Settings.")
        case 403:
            return String(localized: "That key doesn't have access to this model. Try a different model in Settings.")
        case 404:
            return String(localized: "That model isn't available on your account. Try a different one in Settings.")
        case 429:
            return String(localized: "Rate limited by Anthropic. Wait a moment and try again.")
        case 400:
            return apiMessage.isEmpty ? String(localized: "The request was rejected.") : apiMessage
        case 500 ... 599:
            return String(localized: "Anthropic's API is having trouble. Try again shortly.")
        default:
            return apiMessage.isEmpty ? String(localized: "The request failed (HTTP \(status)).") : apiMessage
        }
    }

    /// Converts one stored turn into wire format.
    private static func wireMessage(from message: AssistantMessage) -> [String: Any]? {
        guard message.role != .system else { return nil }
        let role = message.role == .user ? "user" : "assistant"

        // Assistant turns are sent back as plain text: the tool_use blocks from
        // earlier turns were already resolved and replaying them would require
        // their tool_result partners too.
        guard message.role == .user else {
            guard !message.text.isEmpty else { return nil }
            return ["role": role, "content": message.text]
        }

        var blocks: [[String: Any]] = []

        for attachment in message.attachments {
            // Uploaded files are referenced by id, so their bytes cross the
            // wire exactly once no matter how long the conversation runs.
            if let fileID = attachment.remoteFileID {
                switch attachment.kind {
                case .image:
                    blocks.append([
                        "type": "image",
                        "source": ["type": "file", "file_id": fileID],
                    ])
                    continue
                case .pdf:
                    blocks.append([
                        "type": "document",
                        "source": ["type": "file", "file_id": fileID],
                    ])
                    continue
                case .text, .unsupportedSpreadsheet:
                    break
                }
            }

            switch attachment.kind {
            case .image(let mediaType):
                // Upload failed or has not happened yet; inline so the turn
                // still works, at the cost of re-sending on later turns.
                blocks.append([
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": mediaType,
                        "data": attachment.data.base64EncodedString(),
                    ],
                ])
            case .pdf:
                blocks.append([
                    "type": "document",
                    "source": [
                        "type": "base64",
                        "media_type": "application/pdf",
                        "data": attachment.data.base64EncodedString(),
                    ],
                ])
            case .text:
                let text = String(data: attachment.data, encoding: .utf8)
                    ?? String(data: attachment.data, encoding: .isoLatin1)
                    ?? ""
                // Bound the inlined text so one large export can't blow past the
                // request size limit and fail the whole turn.
                blocks.append([
                    "type": "text",
                    "text": "File: \(attachment.filename)\n\n\(String(text.prefix(60_000)))",
                ])
            case .unsupportedSpreadsheet:
                blocks.append([
                    "type": "text",
                    "text": "The user attached \(attachment.filename), which this app can't read. Ask them to export it as CSV and attach that instead.",
                ])
            }
        }

        if !message.text.isEmpty {
            blocks.append(["type": "text", "text": message.text])
        }

        guard !blocks.isEmpty else { return nil }
        return ["role": role, "content": blocks]
    }
}
