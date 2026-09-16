//
//  AddEntryWidget.swift
//  ShiftWidget
//

import SwiftUI
import WidgetKit

/// The widget shows nothing that changes, so its timeline is a single entry
/// that never needs refreshing — and it reads no app data, which is why the
/// extension needs no App Group.
struct AddEntryTimelineEntry: TimelineEntry {
    let date: Date
}

struct AddEntryProvider: TimelineProvider {
    func placeholder(in context: Context) -> AddEntryTimelineEntry {
        AddEntryTimelineEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (AddEntryTimelineEntry) -> Void) {
        completion(AddEntryTimelineEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AddEntryTimelineEntry>) -> Void) {
        completion(Timeline(entries: [AddEntryTimelineEntry(date: .now)], policy: .never))
    }
}

struct AddEntryWidgetView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)

            Text("New Entry")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "shift://new"))
    }
}

struct AddEntryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AddEntryWidget", provider: AddEntryProvider()) { _ in
            AddEntryWidgetView()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text("New Entry"))
        .description(Text("Jump straight to adding an entry."))
        // Small is the smallest size iOS offers — there is no 1×1 widget.
        .supportedFamilies([.systemSmall])
    }
}
