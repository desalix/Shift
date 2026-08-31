//
//  AssistantViewModel.swift
//  Shift
//

import Foundation
import SwiftData
import Observation

/// Drives the chat: builds context, calls the provider, and applies approved
/// proposals to the store.
@Observable
@MainActor
final class AssistantViewModel {
    private(set) var messages: [AssistantMessage] = []
    private(set) var isResponding = false
    var draft: String = ""
    var pendingAttachments: [AssistantAttachment] = []
    /// Proposals the user has already applied, so the UI can show them as done
    /// rather than offering Apply twice.
    private(set) var appliedProposalIDs: Set<UUID> = []

    var hasAPIKey: Bool { KeychainStore.hasAPIKey }

    /// Falls back to the on-device mock whenever no key is configured, so the
    /// Assistant tab is never a dead end.
    private func provider(model: AssistantModel) -> AIProvider {
        hasAPIKey ? AnthropicProvider(model: model.rawValue) : MockAIProvider()
    }

    func send(context: ModelContext, settings: AppSettings) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
        guard !isResponding else { return }

        let userMessage = AssistantMessage(role: .user, text: text, attachments: pendingAttachments)
        messages.append(userMessage)
        draft = ""
        pendingAttachments = []
        isResponding = true

        let assistantContext = buildContext(context: context, settings: settings)
        let selected = settings.assistantModel

        Task {
            // Upload first so the history handed to the provider already carries
            // file ids. Doing it here rather than inside the provider means the
            // ids persist on `messages` and survive into every later turn.
            await uploadAttachmentsIfNeeded()

            do {
                let reply = try await provider(model: selected)
                    .respond(to: messages, context: assistantContext)
                var message = AssistantMessage(role: .assistant, text: reply.text)
                message.proposal = reply.proposal.flatMap { resolveTitles(in: $0, context: context) }
                messages.append(message)
            } catch {
                messages.append(
                    AssistantMessage(
                        role: .assistant,
                        text: error.localizedDescription,
                        isError: true
                    )
                )
            }
            isResponding = false
        }
    }

    func clear() {
        // Uploaded files would otherwise sit on Anthropic's servers
        // indefinitely; clearing the chat should clear them too.
        let staleFileIDs = messages
            .flatMap(\.attachments)
            .compactMap(\.remoteFileID)

        messages.removeAll()
        appliedProposalIDs.removeAll()

        guard !staleFileIDs.isEmpty, let apiKey = KeychainStore.loadAPIKey() else { return }
        Task.detached {
            for fileID in staleFileIDs {
                await AnthropicFiles.delete(fileID: fileID, apiKey: apiKey)
            }
        }
    }

    /// Uploads any attachment that has not been sent yet, recording its id.
    ///
    /// A failure is deliberately not surfaced: the provider falls back to
    /// inlining the bytes, so the turn still works — it just costs more. Making
    /// the user dismiss an alert for a successful message would be worse.
    private func uploadAttachmentsIfNeeded() async {
        guard let apiKey = KeychainStore.loadAPIKey(), !apiKey.isEmpty else { return }

        for messageIndex in messages.indices {
            for attachmentIndex in messages[messageIndex].attachments.indices {
                let attachment = messages[messageIndex].attachments[attachmentIndex]
                guard attachment.isUploadable, attachment.remoteFileID == nil else { continue }

                if let fileID = try? await AnthropicFiles.upload(attachment, apiKey: apiKey) {
                    messages[messageIndex].attachments[attachmentIndex].remoteFileID = fileID
                }
            }
        }
    }

    /// Fills in the real title and date for actions that reference an existing
    /// entry by id.
    ///
    /// The tool decoder is store-independent, so it emits those with empty
    /// placeholders. Resolving them here means the confirmation card can say
    /// "Delete Turno jueves" instead of "Delete an entry" — which matters, since
    /// that card is the only thing standing between the model and the user's
    /// data. An id that no longer resolves is dropped rather than shown as an
    /// unnamed deletion.
    private func resolveTitles(in proposal: AssistantProposal, context: ModelContext) -> AssistantProposal? {
        var resolved: [AssistantAction] = []

        for action in proposal.actions {
            switch action {
            case .deleteEvent(let id, _, _):
                guard let event = fetchEvent(id: id, context: context) else { continue }
                resolved.append(.deleteEvent(id: id, title: event.displayTitle, date: event.startDate))

            case .rescheduleEvent(let id, _, let newStart, let newEnd):
                guard let event = fetchEvent(id: id, context: context) else { continue }
                resolved.append(
                    .rescheduleEvent(id: id, title: event.displayTitle, newStart: newStart, newEnd: newEnd)
                )

            case .createEvent, .createSubject, .enableSchool:
                resolved.append(action)
            }
        }

        // Everything referenced something that no longer exists.
        guard !resolved.isEmpty else { return nil }
        return AssistantProposal(actions: resolved)
    }

    // MARK: - Applying proposals

    /// Applies every action in a proposal, skipping any that fail validation.
    ///
    /// Returns a short summary of what happened so the UI can report partial
    /// success honestly rather than claiming everything worked.
    @discardableResult
    func apply(
        proposal: AssistantProposal,
        context: ModelContext,
        settings: AppSettings,
        errorReporter: AppErrorReporter?
    ) -> String {
        var created = 0
        var deleted = 0
        var moved = 0
        var subjectsAdded = 0
        var rejected = 0

        for action in proposal.actions {
            switch action {
            case .createEvent(let spec):
                if insert(spec: spec, context: context) { created += 1 } else { rejected += 1 }

            case .deleteEvent(let id, _, _):
                if let event = fetchEvent(id: id, context: context) {
                    context.delete(event)
                    deleted += 1
                } else {
                    rejected += 1
                }

            case .rescheduleEvent(let id, _, let newStart, let newEnd):
                if let event = fetchEvent(id: id, context: context), newEnd > newStart {
                    event.startDate = newStart
                    event.endDate = newEnd
                    event.touch()
                    moved += 1
                } else {
                    rejected += 1
                }

            case .createSubject(let name):
                if findSubject(named: name, context: context) == nil {
                    context.insert(Subject(name: name))
                    subjectsAdded += 1
                }

            case .enableSchool:
                settings.schoolEnabled = true
            }
        }

        guard context.saveChanges(reporting: errorReporter, while: String(localized: "Applying changes")) else {
            // The card stays actionable so the user can retry rather than
            // believing changes landed when they did not.
            return String(localized: "Couldn't save those changes.")
        }
        appliedProposalIDs.insert(proposal.id)

        var parts: [String] = []
        if created > 0 { parts.append(String(localized: "\(created) added")) }
        if moved > 0 { parts.append(String(localized: "\(moved) moved")) }
        if deleted > 0 { parts.append(String(localized: "\(deleted) deleted")) }
        if subjectsAdded > 0 { parts.append(String(localized: "\(subjectsAdded) subjects created")) }
        if rejected > 0 { parts.append(String(localized: "\(rejected) skipped")) }

        return parts.isEmpty ? String(localized: "Nothing to apply.") : parts.joined(separator: ", ")
    }

    func discard(proposal: AssistantProposal) {
        appliedProposalIDs.insert(proposal.id)
    }

    /// Validates and inserts one proposed entry. Rejects rather than repairs:
    /// a partially-understood entry is worse than none.
    private func insert(spec: EventSpec, context: ModelContext) -> Bool {
        var subject: Subject?
        if spec.type == .school, let name = spec.subjectName {
            subject = findSubject(named: name, context: context)
            if subject == nil {
                let created = Subject(name: name)
                context.insert(created)
                subject = created
            }
        }

        guard spec.validationErrors(resolvedSubject: subject).isEmpty else { return false }

        let event = Event(
            title: spec.title.trimmingCharacters(in: .whitespacesAndNewlines),
            type: spec.type,
            startDate: spec.startDate,
            endDate: spec.endDate,
            address: spec.address,
            compensationType: spec.compensationType,
            hourlyRateCents: spec.hourlyRateCents,
            fixedRateCents: spec.fixedRateCents,
            schoolKind: spec.schoolKind,
            notes: spec.notes,
            subject: subject
        )
        context.insert(event)
        return true
    }

    private func fetchEvent(id: UUID, context: ModelContext) -> Event? {
        var descriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func findSubject(named name: String, context: ModelContext) -> Subject? {
        let descriptor = FetchDescriptor<Subject>()
        guard let all = try? context.fetch(descriptor) else { return nil }
        return all.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    // MARK: - Context

    /// Assembles what the model is allowed to know: settings, subject and preset
    /// names, and a bounded window of nearby entries.
    private func buildContext(context: ModelContext, settings: AppSettings) -> AssistantContext {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let lower = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let upper = calendar.date(byAdding: .day, value: 60, to: now) ?? now

        var descriptor = FetchDescriptor<Event>(
            predicate: #Predicate<Event> { $0.startDate >= lower && $0.startDate < upper },
            sortBy: [SortDescriptor(\Event.startDate)]
        )
        // Bounded so a heavy calendar can't push the system prompt to an
        // unreasonable size.
        descriptor.fetchLimit = 60

        let events = (try? context.fetch(descriptor)) ?? []
        let subjects = (try? context.fetch(FetchDescriptor<Subject>(sortBy: [SortDescriptor(\Subject.name)]))) ?? []
        let presets = (try? context.fetch(FetchDescriptor<Preset>(sortBy: [SortDescriptor(\Preset.name)]))) ?? []

        return AssistantContext(
            today: now,
            timeZoneIdentifier: TimeZone.current.identifier,
            localeIdentifier: Locale.current.identifier,
            schoolEnabled: settings.schoolEnabled,
            subjectNames: subjects.map(\.name),
            presetNames: presets.map(\.name),
            upcomingEvents: events.map {
                AssistantContext.EventDigest(
                    id: $0.id,
                    title: $0.displayTitle,
                    type: $0.type,
                    start: $0.startDate,
                    end: $0.endDate
                )
            }
        )
    }
}
