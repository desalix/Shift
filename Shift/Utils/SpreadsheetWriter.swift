//
//  SpreadsheetWriter.swift
//  Shift
//

import Foundation

/// Writes a one-sheet `.xlsx`: a bold header row, then one row per entry.
///
/// Cells are typed, not text — dates are dates, times are 24-hour times,
/// durations add up past a day, and money is a number in euros — so the sheet
/// can be summed and sorted in Excel or Numbers without cleaning it up first.
nonisolated enum SpreadsheetWriter {
    enum Cell: Equatable {
        case text(String)
        /// A calendar day, shown in the reader's own date format.
        case date(Date)
        /// A time of day, shown 24-hour ("09:30").
        case time(Date)
        /// A length of time, shown as hours and minutes ("7:30", "27:15").
        case duration(minutes: Int)
        /// An amount in euros, from cents.
        case euros(cents: Int)
        case empty
    }

    /// The workbook for `header` and `rows`. Dates and times are written as the
    /// wall-clock time in `calendar`'s time zone, as the app shows them.
    static func workbook(header: [String], rows: [[Cell]], columnWidths: [Double], calendar: Calendar) -> Data {
        ZipArchive.archive([
            .init(path: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            .init(path: "_rels/.rels", data: Data(rootRelationships.utf8)),
            .init(path: "xl/workbook.xml", data: Data(workbookXML.utf8)),
            .init(path: "xl/_rels/workbook.xml.rels", data: Data(workbookRelationships.utf8)),
            .init(path: "xl/styles.xml", data: Data(stylesXML.utf8)),
            .init(path: "xl/worksheets/sheet1.xml", data: Data(sheetXML(
                header: header, rows: rows, columnWidths: columnWidths, calendar: calendar
            ).utf8)),
        ])
    }

    // MARK: - The sheet

    static func sheetXML(header: [String], rows: [[Cell]], columnWidths: [Double], calendar: Calendar) -> String {
        var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        xml += #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">"#
        // Keep the header in view while scrolling.
        xml += #"<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>"#

        xml += "<cols>"
        for (index, width) in columnWidths.enumerated() {
            xml += #"<col min="\#(index + 1)" max="\#(index + 1)" width="\#(width)" customWidth="1"/>"#
        }
        xml += "</cols><sheetData>"

        xml += #"<row r="1">"#
        for (column, title) in header.enumerated() {
            xml += textCell(title, reference: reference(column: column, row: 1), style: Style.header)
        }
        xml += "</row>"

        for (offset, cells) in rows.enumerated() {
            let row = offset + 2
            xml += #"<row r="\#(row)">"#
            for (column, cell) in cells.enumerated() {
                xml += cellXML(cell, reference: reference(column: column, row: row), calendar: calendar)
            }
            xml += "</row>"
        }

        xml += "</sheetData></worksheet>"
        return xml
    }

    private static func cellXML(_ cell: Cell, reference: String, calendar: Calendar) -> String {
        switch cell {
        case .text(let text):
            return textCell(text, reference: reference, style: Style.plain)
        case .date(let date):
            return numberCell(serialDay(date, calendar: calendar).rounded(.down), reference: reference, style: Style.date)
        case .time(let date):
            let serial = serialDay(date, calendar: calendar)
            return numberCell(serial - serial.rounded(.down), reference: reference, style: Style.time)
        case .duration(let minutes):
            return numberCell(Double(minutes) / 1440, reference: reference, style: Style.duration)
        case .euros(let cents):
            return numberCell(Double(cents) / 100, reference: reference, style: Style.euros)
        case .empty:
            return ""
        }
    }

    private static func textCell(_ text: String, reference: String, style: Int) -> String {
        #"<c r="\#(reference)" t="inlineStr" s="\#(style)"><is><t xml:space="preserve">\#(escaped(text))</t></is></c>"#
    }

    private static func numberCell(_ value: Double, reference: String, style: Int) -> String {
        #"<c r="\#(reference)" s="\#(style)"><v>\#(value)</v></c>"#
    }

    /// "A1", "F12" — columns stop at Z, which is plenty for six.
    private static func reference(column: Int, row: Int) -> String {
        let letter = Character(UnicodeScalar(UInt8(65 + column)))
        return "\(letter)\(row)"
    }

    /// A spreadsheet date: days since 30 December 1899, with the time of day as
    /// the fraction. Built from the wall-clock fields in `calendar`, so 09:00 in
    /// Madrid is 09:00 in the sheet whatever the reader's time zone.
    static func serialDay(_ date: Date, calendar: Calendar) -> Double {
        let fields = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let day = utc.date(from: DateComponents(year: fields.year, month: fields.month, day: fields.day)),
              let epoch = utc.date(from: DateComponents(year: 1899, month: 12, day: 30)),
              let days = utc.dateComponents([.day], from: epoch, to: day).day
        else { return 0 }
        let seconds = (fields.hour ?? 0) * 3600 + (fields.minute ?? 0) * 60 + (fields.second ?? 0)
        return Double(days) + Double(seconds) / 86_400
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Fixed parts

    /// Indexes into `cellXfs` in `stylesXML`.
    private enum Style {
        static let plain = 0
        static let header = 1
        static let date = 2
        static let time = 3
        static let duration = 4
        static let euros = 5
    }

    // Number formats: 14 is the built-in short date, which follows the
    // reader's locale; 20 is the built-in 24-hour "h:mm". 164 lets a duration
    // run past 24 hours; 165 is euros with two decimals.
    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
    <numFmts count="2"><numFmt numFmtId="164" formatCode="[h]:mm"/><numFmt numFmtId="165" formatCode="#,##0.00\\ &quot;€&quot;"/></numFmts>\
    <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>\
    <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>\
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
    <cellXfs count="6">\
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>\
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>\
    <xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    <xf numFmtId="20" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    <xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    </cellXfs>\
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>\
    </styleSheet>
    """

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\
    </Types>
    """

    private static let rootRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
    </Relationships>
    """

    private static let workbookXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
    <sheets><sheet name="Shift" sheetId="1" r:id="rId1"/></sheets>\
    </workbook>
    """

    private static let workbookRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>\
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
    </Relationships>
    """
}
