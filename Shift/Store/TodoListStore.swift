//
//  TodoListStore.swift
//  Shift
//

import Foundation
import Observation
import WidgetKit

/// App-side owner of the to-do text. Every edit is persisted to the App Group
/// immediately; the widget reload is debounced so typing a sentence asks
/// WidgetKit for one refresh, not one per keystroke.
@Observable
@MainActor
final class TodoListStore {
    var text: String {
        didSet {
            guard text != oldValue else { return }
            TodoStorage.save(text: text)
            scheduleWidgetReload()
        }
    }

    @ObservationIgnored
    private var reloadTask: Task<Void, Never>?

    init() {
        text = TodoStorage.loadText()
    }

    private func scheduleWidgetReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadTimelines(ofKind: TodoStorage.widgetKind)
        }
    }
}
