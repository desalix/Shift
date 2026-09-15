//
//  TodoWidgetLayout.swift
//  Shift
//
//  Compiled into both the app and the widget extension.
//

import Foundation

/// Arranges to-do entries into the widget's two columns.
///
/// Cells fill column by column: the left column top to bottom, then the right.
/// When there are more entries than cells, the last cell — bottom right — is
/// given over to a "+N more" count, so it always reports how many are hidden
/// rather than silently dropping them.
nonisolated struct TodoWidgetLayout: Equatable {
    enum Cell: Equatable {
        case entry(String)
        case overflow(Int)
    }

    let left: [Cell]
    let right: [Cell]

    init(entries: [String], rowsPerColumn: Int) {
        let rows = max(1, rowsPerColumn)
        let capacity = rows * 2

        let cells: [Cell]
        if entries.count <= capacity {
            cells = entries.map(Cell.entry)
        } else {
            // The overflow cell takes one slot itself.
            let shown = capacity - 1
            cells = entries.prefix(shown).map(Cell.entry) + [.overflow(entries.count - shown)]
        }

        left = Array(cells.prefix(rows))
        right = Array(cells.dropFirst(rows))
    }
}
