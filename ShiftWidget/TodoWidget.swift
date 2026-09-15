//
//  TodoWidget.swift
//  ShiftWidget
//

import SwiftUI
import WidgetKit

struct TodoTimelineEntry: TimelineEntry {
    let date: Date
    let entries: [String]
}

struct TodoProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoTimelineEntry {
        TodoTimelineEntry(date: .now, entries: ["Buy milk", "Gym", "Call mum", "Pay rent"])
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoTimelineEntry) -> Void) {
        let current = currentEntry()
        // The widget gallery shows the snapshot before any to-dos exist; an
        // empty preview would sell the widget as blank.
        completion(context.isPreview && current.entries.isEmpty ? placeholder(in: context) : current)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoTimelineEntry>) -> Void) {
        // `.never`: the app asks WidgetKit to reload whenever the list changes,
        // so there is nothing to poll for.
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> TodoTimelineEntry {
        TodoTimelineEntry(date: .now, entries: TodoStorage.entries(from: TodoStorage.loadText()))
    }
}

struct TodoWidgetView: View {
    let entry: TodoTimelineEntry

    private let rowsPerColumn = 5

    var body: some View {
        Group {
            if entry.entries.isEmpty {
                Text("No to-dos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let layout = TodoWidgetLayout(entries: entry.entries, rowsPerColumn: rowsPerColumn)
                HStack(alignment: .top, spacing: 12) {
                    column(layout.left)
                    column(layout.right)
                }
            }
        }
        .widgetURL(URL(string: "shift://todo"))
    }

    private func column(_ cells: [TodoWidgetLayout.Cell]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                switch cell {
                case .entry(let text):
                    Text(text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                case .overflow(let count):
                    Text("+\(count) more")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct TodoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodoStorage.widgetKind, provider: TodoProvider()) { entry in
            TodoWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text("To-Do"))
        .description(Text("Your to-do list at a glance."))
        .supportedFamilies([.systemMedium])
    }
}
