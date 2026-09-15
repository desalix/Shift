//
//  ExportView.swift
//  Shift
//

import SwiftUI
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

/// Pick one or more months and share them as a JSON file.
struct ExportView: View {
    @Query(sort: \Event.startDate, order: .reverse) private var events: [Event]

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    @State private var selectedMonths: Set<Date> = []

    var body: some View {
        let months = MonthExporter.availableMonths(for: events, calendar: calendar)

        List {
            if months.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to export", systemImage: "square.and.arrow.up")
                } description: {
                    Text("Months with entries will appear here.")
                }
            } else {
                Section {
                    ForEach(months, id: \.start) { month in
                        Button {
                            toggle(month.start)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(month.start.formatted(.dateTime.month(.wide).year().locale(locale)).localizedCapitalized)
                                        .foregroundStyle(.primary)
                                    Text("\(month.entryCount) entries")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedMonths.contains(month.start) {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedMonths.contains(month.start) ? .isSelected : [])
                    }
                } footer: {
                    Text("Choose one or more months. Entries are grouped by the month they start in.")
                }
            }
        }
        .navigationTitle(Text("Export"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !months.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    let allSelected = selectedMonths.count == months.count
                    Button(allSelected ? String(localized: "Select None") : String(localized: "Select All")) {
                        selectedMonths = allSelected ? [] : Set(months.map(\.start))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !months.isEmpty {
                ShareLink(item: exportFile, preview: SharePreview(exportFile.fileName)) {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedMonths.isEmpty)
                .padding()
            }
        }
    }

    private func toggle(_ month: Date) {
        if selectedMonths.contains(month) {
            selectedMonths.remove(month)
        } else {
            selectedMonths.insert(month)
        }
    }

    /// Encoded on the main actor, where the model objects live; the share sheet
    /// then only has to write bytes.
    private var exportFile: MonthExportFile {
        let months = Array(selectedMonths)
        let document = MonthExporter.makeDocument(events: events, months: months, calendar: calendar)
        let data = (try? MonthExporter.encode(document, timeZone: calendar.timeZone)) ?? Data()
        return MonthExportFile(data: data, fileName: MonthExporter.fileName(for: months, calendar: calendar))
    }
}

/// The JSON handed to the share sheet, written to a temporary file so the
/// recipient sees a real file name rather than a generic "data".
nonisolated struct MonthExportFile: Transferable {
    let data: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { file in
            let url = URL.temporaryDirectory.appending(path: file.fileName)
            try file.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
