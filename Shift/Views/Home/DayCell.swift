//
//  DayCell.swift
//  Shift
//

import SwiftUI

/// One box in the month grid.
///
/// Work defines the day: a working day is tinted end to end and names the shift
/// in bold under the date. School and calendar entries are the day's contents
/// rather than its character, so they stay as chips below, with the overflow
/// folded into a "+N More" line.
struct DayCell: View {
    let day: Date
    let events: [Event]
    let isInDisplayedMonth: Bool
    let isToday: Bool

    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let chipHeight: CGFloat = 14
    private let chipSpacing: CGFloat = 1.5
    private let headlineHeight: CGFloat = 15

    var body: some View {
        let summary = WorkDaySummary(events: events)

        GeometryReader { proxy in
            let capacity = slotCapacity(in: proxy.size.height, hasHeadline: summary.headline != nil)
            let layout = ChipLayout(total: summary.otherEvents.count, capacity: capacity)

            VStack(alignment: .leading, spacing: chipSpacing) {
                dayNumber

                if let headline = summary.headline {
                    workHeadline(headline, summary: summary)
                }

                ForEach(summary.otherEvents.prefix(layout.visibleCount)) { event in
                    EventChip(event: event, height: chipHeight)
                }

                if layout.overflowCount > 0 {
                    Text("+\(layout.overflowCount) More")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(height: chipHeight, alignment: .leading)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(background(for: summary))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: summary))
        .accessibilityAddTraits(.isButton)
    }

    /// Tint sits over the normal backing so out-of-month days stay recessed
    /// even when they are working days.
    private func background(for summary: WorkDaySummary) -> some View {
        let base = isInDisplayedMonth ? Color(.systemBackground) : Color(.secondarySystemBackground)
        return ZStack {
            base
            if let lead = summary.leadEvent {
                settings.color(for: lead).opacity(isInDisplayedMonth ? 0.18 : 0.10)
            }
        }
    }

    private var dayNumber: some View {
        Text(day.formatted(.dateTime.day()))
            .font(.system(size: 11, weight: isToday ? .bold : .regular))
            .monospacedDigit()
            .foregroundStyle(numberColor)
            .frame(minWidth: 17, minHeight: 17)
            .background {
                if isToday {
                    Circle().fill(settings.accentColor.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The shift's name (or a count), a step larger and heavier than the chips
    /// so the day reads as "work" before anything else does.
    private func workHeadline(_ headline: String, summary: WorkDaySummary) -> some View {
        HStack(spacing: 3) {
            Text(headline)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
                .layoutPriority(-1)

            if summary.showsRecurrenceMarker, let lead = summary.leadEvent {
                let color = settings.color(for: lead)
                if horizontalSizeClass == .regular {
                    Text("Rec")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(color)
                        .fixedSize()
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 3.5, height: 3.5)
                        .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: headlineHeight)
    }

    private var numberColor: Color {
        if isToday { return .white }
        return isInDisplayedMonth ? .primary : .secondary
    }

    /// How many chip-sized rows fit below the day number, once the work
    /// headline has taken its share.
    private func slotCapacity(in height: CGFloat, hasHeadline: Bool) -> Int {
        let dayNumberBlock: CGFloat = 17 + chipSpacing
        let headlineBlock: CGFloat = hasHeadline ? headlineHeight + chipSpacing : 0
        let usable = height - dayNumberBlock - headlineBlock - 4
        guard usable > 0 else { return 0 }
        return max(0, Int(usable / (chipHeight + chipSpacing)))
    }

    private func accessibilityLabel(for summary: WorkDaySummary) -> Text {
        let dateText = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if summary.isWorkDay {
            return Text("\(dateText), work day")
        }
        if events.isEmpty {
            return Text("\(dateText), no entries")
        }
        return Text("\(dateText), \(events.count) entries")
    }
}

/// Works out how many chips to draw and how many to fold into "+N More".
///
/// The overflow line occupies a slot itself, so showing it costs one chip —
/// which is why this isn't simply `min(total, capacity)`.
struct ChipLayout {
    let visibleCount: Int
    let overflowCount: Int

    init(total: Int, capacity: Int) {
        guard capacity > 0 else {
            visibleCount = 0
            overflowCount = total
            return
        }
        if total <= capacity {
            visibleCount = total
            overflowCount = 0
        } else {
            // Reserve the last slot for the "+N More" line.
            visibleCount = capacity - 1
            overflowCount = total - (capacity - 1)
        }
    }
}

private struct EventChip: View {
    let event: Event
    let height: CGFloat

    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        // The spec asks for a literal "Rec" label, which fits on an iPad cell but
        // not an iPhone one. Choose by size class rather than by measuring:
        // `ViewThatFits` compares against the title's *untruncated* width, so it
        // would discard the marker on almost every real title.
        let marker: RecurrenceMarker = horizontalSizeClass == .regular ? .label : .dot
        chip(color: settings.color(for: event), marker: marker)
            .frame(height: height)
    }

    private enum RecurrenceMarker { case label, dot }

    private func chip(color: Color, marker: RecurrenceMarker) -> some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(color)
                .frame(width: 2.5)

            Text(event.displayTitle)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
                // Yield space to the marker rather than pushing it out.
                .layoutPriority(-1)

            if event.isRecurring {
                switch marker {
                case .label:
                    Text("Rec")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(color)
                        .fixedSize()
                case .dot:
                    Circle()
                        .fill(color)
                        .frame(width: 3.5, height: 3.5)
                        .fixedSize()
                }
            }
        }
        .padding(.trailing, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}
