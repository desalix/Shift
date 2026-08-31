//
//  MessageBubble.swift
//  Shift
//

import SwiftUI
import Combine

/// One turn in the transcript, plus the proposal card when the assistant has
/// suggested changes.
struct MessageBubble: View {
    let message: AssistantMessage
    let isApplied: Bool
    let onApply: (AssistantProposal) -> Void
    let onDiscard: (AssistantProposal) -> Void

    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            if !message.attachments.isEmpty {
                HStack(spacing: 6) {
                    ForEach(message.attachments) { attachment in
                        AttachmentChip(attachment: attachment, onRemove: nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            }

            if !message.text.isEmpty {
                Text(message.text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(bubbleForeground)
                    .frame(maxWidth: 520, alignment: message.role == .user ? .trailing : .leading)
            }

            if let proposal = message.proposal {
                ProposalCard(
                    proposal: proposal,
                    isApplied: isApplied,
                    onApply: { onApply(proposal) },
                    onDiscard: { onDiscard(proposal) }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var bubbleBackground: Color {
        if message.isError { return Color.orange.opacity(0.15) }
        return message.role == .user
            ? settings.accentColor.color
            : Color(.secondarySystemGroupedBackground)
    }

    private var bubbleForeground: Color {
        if message.isError { return .primary }
        return message.role == .user ? .white : .primary
    }
}

/// The review step. Nothing reaches the store until the user acts on this card,
/// and destructive batches say so before they are applied.
struct ProposalCard: View {
    let proposal: AssistantProposal
    let isApplied: Bool
    let onApply: () -> Void
    let onDiscard: () -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(AppSettings.self) private var settings

    @State private var isConfirmingDestructive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(proposal.actions.prefix(12).enumerated()), id: \.offset) { index, action in
                    if index > 0 { Divider().padding(.leading, 34) }
                    ActionRow(action: action)
                }

                if proposal.actions.count > 12 {
                    Divider().padding(.leading, 34)
                    Text("+\(proposal.actions.count - 12) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }

            if !isApplied {
                Divider()
                buttons
            }
        }
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        }
        .frame(maxWidth: 520)
        .confirmationDialog(
            Text("Apply these changes?"),
            isPresented: $isConfirmingDestructive,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Apply"), role: .destructive, action: onApply)
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("This will change or remove entries that already exist.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: isApplied ? "checkmark.circle.fill" : "wand.and.stars")
                .foregroundStyle(isApplied ? .green : settings.accentColor.color)

            Text(isApplied
                 ? String(localized: "Applied")
                 : String(localized: "^[\(proposal.actions.count) change](inflect: true)"))
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 0)

            if proposal.containsDestructive && !isApplied {
                Label("Modifies existing", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var buttons: some View {
        HStack(spacing: 0) {
            Button(role: .cancel, action: onDiscard) {
                Text("Discard")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }

            Divider().frame(height: 40)

            Button {
                if proposal.containsDestructive {
                    isConfirmingDestructive = true
                } else {
                    onApply()
                }
            } label: {
                Text("Apply")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(settings.accentColor.color)
    }
}

private struct ActionRow: View {
    let action: AssistantAction

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: action.symbolName)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .lineLimit(2)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var title: String {
        switch action {
        case .createEvent(let spec):
            spec.title.isEmpty ? String(localized: "New entry") : spec.title
        case .deleteEvent(_, let title, _):
            title.isEmpty ? String(localized: "Delete an entry") : String(localized: "Delete \(title)")
        case .rescheduleEvent(_, let title, _, _):
            title.isEmpty ? String(localized: "Move an entry") : String(localized: "Move \(title)")
        case .createSubject(let name):
            String(localized: "New subject: \(name)")
        case .enableSchool:
            String(localized: "Turn on the School section")
        }
    }

    private var detail: String? {
        switch action {
        case .createEvent(let spec):
            var parts: [String] = [
                spec.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute().locale(locale)),
                "–",
                spec.endDate.formatted(.dateTime.hour().minute().locale(locale)),
            ]
            if let cents = spec.hourlyRateCents {
                parts.append("· \(Money.string(cents: cents, locale: locale))/h")
            } else if let cents = spec.fixedRateCents {
                parts.append("· \(Money.string(cents: cents, locale: locale))")
            }
            return parts.joined(separator: " ")

        case .rescheduleEvent(_, _, let start, let end):
            return "\(start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute().locale(locale))) – \(end.formatted(.dateTime.hour().minute().locale(locale)))"

        case .deleteEvent, .createSubject, .enableSchool:
            return nil
        }
    }
}

/// A small file pill, used both in the composer (removable) and in sent
/// messages (fixed).
struct AttachmentChip: View {
    let attachment: AssistantAttachment
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: attachment.symbolName)
                .font(.caption)
            Text(attachment.filename)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 130)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove attachment"))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

/// Three-dot activity indicator shown while a reply is in flight.
struct TypingIndicator: View {
    @State private var phase = 0

    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< 3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(phase == index ? 1 : 0.3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                phase = (phase + 1) % 3
            }
        }
        .accessibilityLabel(Text("Thinking"))
    }
}
