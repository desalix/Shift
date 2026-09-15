//
//  AssistantView.swift
//  Shift
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

/// The chat tab. No month stepper here — the assistant isn't scoped to a month.
struct AssistantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Environment(AppErrorReporter.self) private var errorReporter

    @State private var model = AssistantViewModel()
    @State private var isImportingFile = false
    @State private var importError: String?

    var body: some View {
        transcript
            // A safe-area inset rather than a VStack sibling, so the composer
            // sits above the system tab bar and the transcript scrolls under it.
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .background(Color(.systemGroupedBackground))
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: Self.allowedTypes,
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .alert(
            Text("Couldn't attach file"),
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button(String(localized: "OK"), role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if model.messages.isEmpty {
                        emptyState
                            .padding(.top, 40)
                    }

                    ForEach(model.messages) { message in
                        MessageBubble(
                            message: message,
                            isApplied: message.proposal.map { model.appliedProposalIDs.contains($0.id) } ?? false,
                            onApply: { proposal in
                                let summary = model.apply(
                                    proposal: proposal,
                                    context: modelContext,
                                    settings: settings,
                                    errorReporter: errorReporter
                                )
                                announce(summary)
                            },
                            onDiscard: { proposal in
                                model.discard(proposal: proposal)
                            }
                        )
                        .id(message.id)
                    }

                    if model.isResponding {
                        TypingIndicator()
                            .id(Self.typingIndicatorID)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: model.isResponding) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private static let typingIndicatorID = "typing"

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.snappy(duration: 0.25)) {
            if model.isResponding {
                proxy.scrollTo(Self.typingIndicatorID, anchor: .bottom)
            } else if let last = model.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 38))
                .foregroundStyle(settings.accentColor.color)
                .symbolRenderingMode(.hierarchical)

            Text("Ask me to build your schedule")
                .font(.headline)

            Text(model.hasAPIKey
                 ? String(localized: "Describe your shifts in plain language, or attach a rota and I'll read it.")
                 : String(localized: "Running in demo mode. Add your Anthropic API key in Settings for the full assistant."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button {
                        model.draft = suggestion
                    } label: {
                        Text(suggestion)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private static var suggestions: [String] {
        [
            String(localized: "Add a shift every Thursday 14:30-19:00 at 12.50/h until September, skipping alternate weeks"),
            String(localized: "Move my Friday shift to Saturday same time"),
            String(localized: "What am I earning this month?"),
        ]
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 8) {
            if !model.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.pendingAttachments) { attachment in
                            AttachmentChip(attachment: attachment) {
                                model.pendingAttachments.removeAll { $0.id == attachment.id }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(height: 34)
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    isImportingFile = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 19))
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel(Text("Attach file"))

                TextField("Message", text: $model.draft, axis: .vertical)
                    .lineLimit(1 ... 5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )

                Button {
                    model.send(context: modelContext, settings: settings)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(!canSend)
                .accessibilityLabel(Text("Send"))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .background(.bar)
    }

    private var canSend: Bool {
        !model.isResponding
            && (!model.draft.trimmingCharacters(in: .whitespaces).isEmpty || !model.pendingAttachments.isEmpty)
    }

    private func announce(_ summary: String) {
        UIAccessibility.post(notification: .announcement, argument: summary)
    }

    // MARK: - File import

    private static var allowedTypes: [UTType] {
        // Spreadsheets are accepted so the user isn't blocked at the picker;
        // xlsx/xls are then flagged in-app with an explanation.
        [
            .commaSeparatedText, .pdf, .png, .jpeg, .plainText,
            UTType(filenameExtension: "xlsx") ?? .data,
            UTType(filenameExtension: "xls") ?? .data,
        ]
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else {
                    importError = String(localized: "Couldn't open \(url.lastPathComponent).")
                    continue
                }
                defer { url.stopAccessingSecurityScopedResource() }

                guard let data = try? Data(contentsOf: url) else {
                    importError = String(localized: "Couldn't read \(url.lastPathComponent).")
                    continue
                }

                // 12 MB keeps a base64-inlined attachment comfortably inside the
                // API's request size limit.
                guard data.count <= 12 * 1024 * 1024 else {
                    importError = String(localized: "\(url.lastPathComponent) is too large. The limit is 12 MB.")
                    continue
                }

                model.pendingAttachments.append(
                    AssistantAttachment(
                        filename: url.lastPathComponent,
                        kind: Self.kind(for: url),
                        data: data
                    )
                )
            }
        }
    }

    private static func kind(for url: URL) -> AssistantAttachment.Kind {
        switch url.pathExtension.lowercased() {
        case "png": .image(mediaType: "image/png")
        case "jpg", "jpeg": .image(mediaType: "image/jpeg")
        case "pdf": .pdf
        case "csv", "txt": .text
        case "xlsx", "xls": .unsupportedSpreadsheet
        default: .text
        }
    }
}
