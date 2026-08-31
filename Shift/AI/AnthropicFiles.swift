//
//  AnthropicFiles.swift
//  Shift
//

import Foundation

/// Uploads attachments to the Anthropic Files API so they can be referenced by
/// id instead of being re-encoded into every request.
///
/// The Messages API is stateless: the whole conversation is re-sent each turn.
/// Inlining a 12 MB rota as base64 therefore re-uploads and re-bills it on every
/// follow-up message. Uploading once and referencing the returned `file_id`
/// makes each attachment cost exactly one upload, no matter how long the
/// conversation runs — and unlike dropping old attachments, it keeps them
/// readable, so "also add the Saturdays from that PDF" still works.
enum AnthropicFiles {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/files")!
    private static let apiVersion = "2023-06-01"

    /// Required on the upload *and* on any message that references the file.
    static let betaHeader = "files-api-2025-04-14"

    /// Uploads one attachment and returns its `file_id`.
    ///
    /// Only PDFs and images are worth uploading — text is inlined directly and
    /// is already length-capped, so a round trip would cost more than it saves.
    static func upload(
        _ attachment: AssistantAttachment,
        apiKey: String,
        session: URLSession = .shared
    ) async throws -> String {
        let boundary = "----shift-\(UUID().uuidString)"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = multipartBody(for: attachment, boundary: boundary)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIProviderError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw AIProviderError.malformedResponse
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            let message = (payload["error"] as? [String: Any])?["message"] as? String ?? ""
            throw AIProviderError.http(status: http.statusCode, message: message)
        }

        guard let id = payload["id"] as? String else {
            throw AIProviderError.malformedResponse
        }
        return id
    }

    /// Best-effort cleanup when a conversation is cleared.
    ///
    /// Uploaded files otherwise persist on Anthropic's servers indefinitely,
    /// which for someone's work rota is not a reasonable default. Failures are
    /// ignored: the file may already be gone, and there is nothing useful to
    /// tell the user at this point.
    static func delete(
        fileID: String,
        apiKey: String,
        session: URLSession = .shared
    ) async {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return }
        components.path += "/\(fileID)"
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")

        _ = try? await session.data(for: request)
    }

    private static func multipartBody(for attachment: AssistantAttachment, boundary: String) -> Data {
        var body = Data()

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(sanitised(attachment.filename))\"\r\n")
        append("Content-Type: \(attachment.mimeType)\r\n\r\n")
        body.append(attachment.data)
        append("\r\n--\(boundary)--\r\n")

        return body
    }

    /// Strips characters that would break the multipart header, which is a
    /// plain-text protocol — a filename containing a quote or newline could
    /// otherwise inject header fields.
    private static func sanitised(_ filename: String) -> String {
        let cleaned = filename
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        return cleaned.isEmpty ? "attachment" : cleaned
    }
}
