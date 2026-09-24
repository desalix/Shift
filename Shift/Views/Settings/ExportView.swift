//
//  ExportView.swift
//  Shift
//

import SwiftUI
import SwiftData
import CoreTransferable
import UniformTypeIdentifiers

/// Pick one or more months and share their work entries as a spreadsheet.
struct ExportView: View {
    @Query(
        filter: #Predicate<Event> { $0.typeRaw == "work" },
        sort: \Event.startDate,
        order: .reverse
    ) private var events: [Event]

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
                    Text("Months with work entries will appear here.")
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
                                    Text("\(month.entryCount) shifts")
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
                    Text("Choose one or more months. Their work entries are exported as a spreadsheet, in date order.")
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

    /// The rows are gathered on the main actor, where the model objects live;
    /// the spreadsheet is written only when the share sheet asks for the file.
    private var exportFile: MonthExportFile {
        let months = Array(selectedMonths)
        return MonthExportFile(
            header: MonthExporter.header,
            rows: MonthExporter.rows(events: events, months: months, calendar: calendar),
            calendar: calendar,
            fileName: MonthExporter.fileName(for: months, calendar: calendar)
        )
    }
}

/// The spreadsheet handed to the share sheet, written to a temporary file so
/// the recipient sees a real file name rather than a generic "data".
///
/// Written here, not in the view body, so it happens once per share rather
/// than on every redraw.
nonisolated struct MonthExportFile: Transferable {
    let header: [String]
    let rows: [MonthExporter.Row]
    let calendar: Calendar
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .xlsx) { file in
            let data = MonthExporter.spreadsheet(header: file.header, rows: file.rows, calendar: file.calendar)
            let url = URL.temporaryDirectory.appending(path: file.fileName)
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

extension UTType {
    /// Excel's `.xlsx`. Declared by the system; the fallback only guards the
    /// lookup, since the constant needs a value.
    nonisolated static let xlsx = UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data
}
