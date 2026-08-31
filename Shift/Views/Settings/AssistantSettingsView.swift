//
//  AssistantSettingsView.swift
//  Shift
//

import SwiftUI

/// Connects the Assistant to Anthropic using a key the user supplies.
///
/// The app never ships a key of its own and never proxies requests, so the
/// user's usage is billed to their own Anthropic account and their key never
/// leaves the device.
struct AssistantSettingsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var apiKeyField = ""
    @State private var storedKeyPreview: String?
    @State private var errorMessage: String?
    @State private var didSave = false

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                if let preview = storedKeyPreview {
                    LabeledContent {
                        Text(preview)
                            .monospaced()
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("API Key", systemImage: "key.fill")
                    }

                    Button(role: .destructive) {
                        removeKey()
                    } label: {
                        Label("Remove Key", systemImage: "trash")
                    }
                } else {
                    SecureField("sk-ant-…", text: $apiKeyField)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(saveKey)

                    Button {
                        saveKey()
                    } label: {
                        Label("Save Key", systemImage: "checkmark.circle")
                    }
                    .disabled(apiKeyField.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if didSave {
                    Label("Saved to Keychain", systemImage: "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Anthropic API Key")
            } footer: {
                Text("Stored in the device Keychain and sent only to api.anthropic.com. Usage is billed to your own Anthropic account. Files you attach are uploaded to Anthropic so they don't have to be re-sent with every message, and are deleted when you clear the conversation. Get a key at console.anthropic.com.")
            }

            Section {
                Picker(selection: $settings.assistantModel) {
                    ForEach(AssistantModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                } label: {
                    Label("Model", systemImage: "cpu")
                }

                Text(settings.assistantModel.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Model")
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Without a key")
                            .font(.subheadline.weight(.medium))
                        Text("The Assistant still runs in demo mode: it understands a useful set of requests offline and proposes the same changes, so you can try it before connecting anything.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "info.circle")
                }
            }
        }
        .navigationTitle(Text("AI Assistant"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshStoredKey)
    }

    /// Shows only the last four characters — enough to confirm *which* key is
    /// installed without putting the secret back on screen.
    private func refreshStoredKey() {
        guard let key = KeychainStore.loadAPIKey(), key.count > 4 else {
            storedKeyPreview = KeychainStore.loadAPIKey() == nil ? nil : "••••"
            return
        }
        storedKeyPreview = "••••••••" + key.suffix(4)
    }

    private func saveKey() {
        errorMessage = nil
        let candidate = apiKeyField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }

        do {
            try KeychainStore.save(apiKey: candidate)
            apiKeyField = ""
            didSave = true
            refreshStoredKey()
            Task {
                try? await Task.sleep(for: .seconds(2))
                didSave = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeKey() {
        errorMessage = nil
        do {
            try KeychainStore.deleteAPIKey()
            storedKeyPreview = nil
            didSave = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
