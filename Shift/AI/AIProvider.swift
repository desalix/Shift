//
//  AIProvider.swift
//  Shift
//

import Foundation

/// One turn in the conversation.
struct AssistantMessage: Identifiable, Sendable {
    enum Role: Sendable { case user, assistant, system }

    let id = UUID()
    var role: Role
    var text: String
    var attachments: [AssistantAttachment] = []
    var proposal: AssistantProposal?
    var isError: Bool = false
    var timestamp: Date = Date()
}

/// A file the user attached to a message.
struct AssistantAttachment: Identifiable, Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case image(mediaType: String)
        case pdf
        case text
        /// Recognised but not readable in-app — the user is told what to do.
        case unsupportedSpreadsheet
    }

    let id = UUID()
    var filename: String
    var kind: Kind
    var data: Data

    /// Set once the file has been uploaded to the Files API. Present means the
    /// bytes never need to go over the wire again.
    var remoteFileID: String?

    /// Whether uploading this attachment is worthwhile. Text is inlined
    /// directly and already length-capped, so a round trip would cost more than
    /// it saves; spreadsheets we cannot read are never sent at all.
    var isUploadable: Bool {
        switch kind {
        case .image, .pdf: true
        case .text, .unsupportedSpreadsheet: false
        }
    }

    var mimeType: String {
        switch kind {
        case .image(let mediaType): mediaType
        case .pdf: "application/pdf"
        case .text: "text/plain"
        case .unsupportedSpreadsheet: "application/octet-stream"
        }
    }

    var symbolName: String {
        switch kind {
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .text: "tablecells"
        case .unsupportedSpreadsheet: "exclamationmark.triangle"
        }
    }
}

/// What the app knows about the user's current state, handed to the model so it
/// can resolve relative dates and respect whether School is enabled.
struct AssistantContext: Sendable {
    var today: Date
    var timeZoneIdentifier: String
    var localeIdentifier: String
    var schoolEnabled: Bool
    var subjectNames: [String]
    var presetNames: [String]
    /// A compact digest of nearby entries so the model can reference and modify
    /// them by id without being handed the whole database.
    var upcomingEvents: [EventDigest]

    struct EventDigest: Sendable {
        var id: UUID
        var title: String
        var type: EventType
        var start: Date
        var end: Date
    }
}

/// Result of one assistant turn.
struct AssistantReply: Sendable {
    var text: String
    var proposal: AssistantProposal?
}

enum AIProviderError: LocalizedError {
    case missingAPIKey
    case http(status: Int, message: String)
    case malformedResponse
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            String(localized: "Add your Anthropic API key in Settings to use the Assistant.")
        case .http(let status, let message):
            message.isEmpty
                ? String(localized: "The request failed (HTTP \(status)).")
                : message
        case .malformedResponse:
            String(localized: "The response could not be read.")
        case .transport(let message):
            message
        }
    }
}

/// Abstraction over "something that can answer a turn".
///
/// Two implementations ship: a mock that runs entirely on device, and one that
/// calls the Anthropic API with the user's own key. The chat UI is written
/// against this protocol so neither is load-bearing for the other.
protocol AIProvider: Sendable {
    func respond(
        to history: [AssistantMessage],
        context: AssistantContext
    ) async throws -> AssistantReply
}
