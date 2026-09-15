//
//  TodoView.swift
//  Shift
//

import SwiftUI

/// A plain to-do list: one entry per line, return starts the next.
struct TodoView: View {
    @Environment(TodoListStore.self) private var store
    @FocusState private var isEditing: Bool

    var body: some View {
        @Bindable var store = store

        TextEditor(text: $store.text)
            .focused($isEditing)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 12)
            .overlay(alignment: .topLeading) {
                if store.text.isEmpty {
                    Text("One to-do per line.")
                        .foregroundStyle(.tertiary)
                        // Aligns with the editor's own text inset.
                        .padding(.horizontal, 17)
                        .padding(.top, 8)
                        .allowsHitTesting(false)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                if isEditing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isEditing = false }
                    }
                }
            }
    }
}
