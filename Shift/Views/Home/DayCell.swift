//
//  DayCell.swift
//  Shift
//

import SwiftUI

/// One box in the month grid.
///
/// Fits as many event chips as the box height allows and collapses the rest
/// into a "+N More" line. Tapping anywhere in the cell — including that line —
/// opens the full scrollable day list.
struct DayCell: View {
    let day: Date
    let events: [Event]
    let isInDisplayedMonth: Bool
    let isToday: Bool

    @Environment(AppSettings.self) private var settings
    @Environment(\.calendar) private var calendar

    private let chipHeight: CGFloat = 14
    private let chipSpacing: CGFloat = 1.5

    var body: some View {
        GeometryReader { proxy in
            let capacity = slotCapacity(in: proxy.size.height)
            let layout = ChipLayout(total: events.count, capacity: capacity)

            VStack(alignment: .leading, spacing: chipSpacing) {
                dayNumber

                ForEach(events.prefix(layout.visibleCount)) { event in
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
        .background(isInDisplayedMonth ? Color(.systemBackground) : Color(.secondarySystemBackground))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
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

    private var numberColor: Color {
        if isToday { return .white }
        return isInDisplayedMonth ? .primary : .secondary
    }

    /// How many chip-sized rows fit below the day number.
    private func slotCapacity(in height: CGFloat) -> Int {
        let dayNumberBlock: CGFloat = 17 + chipSpacing
        let usable = height - dayNumberBlock - 4
        guard usable > 0 else { return 0 }
        return max(0, Int(usable / (chipHeight + chipSpacing)))
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

extension DayCell {
    private var accessibilityLabel: Text {
        let dateText = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if events.isEmpty {
            return Text("\(dateText), no entries")
        }
        return Text("\(dateText), \(events.count) entries")
    }
}
