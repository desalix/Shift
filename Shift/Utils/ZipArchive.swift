//
//  ZipArchive.swift
//  Shift
//

import Foundation

/// Just enough of the ZIP format to package an `.xlsx`, which is a zip of XML
/// files.
///
/// Entries are stored, not compressed: a month of shifts is a few kilobytes,
/// every spreadsheet app reads stored entries, and it keeps this free of any
/// compression library.
nonisolated enum ZipArchive {
    struct Entry {
        let path: String
        let data: Data
    }

    /// A complete archive holding `entries`, in the order given.
    static func archive(_ entries: [Entry]) -> Data {
        var archive = Data()
        var centralDirectory = Data()

        for entry in entries {
            let name = Data(entry.path.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(archive.count)

            // Local file header.
            archive.append(uint32: 0x0403_4B50)
            archive.append(uint16: 20)          // version needed: 2.0
            archive.append(uint16: 0)           // flags
            archive.append(uint16: 0)           // method: stored
            archive.append(uint16: dosTime)
            archive.append(uint16: dosDate)
            archive.append(uint32: crc)
            archive.append(uint32: size)        // compressed size
            archive.append(uint32: size)        // uncompressed size
            archive.append(uint16: UInt16(name.count))
            archive.append(uint16: 0)           // extra field length
            archive.append(name)
            archive.append(entry.data)

            // Its central directory record.
            centralDirectory.append(uint32: 0x0201_4B50)
            centralDirectory.append(uint16: 20) // version made by
            centralDirectory.append(uint16: 20) // version needed
            centralDirectory.append(uint16: 0)
            centralDirectory.append(uint16: 0)
            centralDirectory.append(uint16: dosTime)
            centralDirectory.append(uint16: dosDate)
            centralDirectory.append(uint32: crc)
            centralDirectory.append(uint32: size)
            centralDirectory.append(uint32: size)
            centralDirectory.append(uint16: UInt16(name.count))
            centralDirectory.append(uint16: 0)  // extra field length
            centralDirectory.append(uint16: 0)  // comment length
            centralDirectory.append(uint16: 0)  // disk number
            centralDirectory.append(uint16: 0)  // internal attributes
            centralDirectory.append(uint32: 0)  // external attributes
            centralDirectory.append(uint32: offset)
            centralDirectory.append(name)
        }

        let directoryOffset = UInt32(archive.count)
        archive.append(centralDirectory)

        // End of central directory.
        archive.append(uint32: 0x0605_4B50)
        archive.append(uint16: 0)               // this disk
        archive.append(uint16: 0)               // disk with the directory
        archive.append(uint16: UInt16(entries.count))
        archive.append(uint16: UInt16(entries.count))
        archive.append(uint32: UInt32(centralDirectory.count))
        archive.append(uint32: directoryOffset)
        archive.append(uint16: 0)               // comment length

        return archive
    }

    /// 1 January 1980, 00:00 — the earliest DOS timestamp. File times inside
    /// an export mean nothing, and a fixed one keeps the output reproducible.
    private static let dosTime: UInt16 = 0
    private static let dosDate: UInt16 = (0 << 9) | (1 << 5) | 1

    /// The CRC-32 every zip entry carries (IEEE polynomial, reflected).
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let crcTable: [UInt32] = (0 ..< 256).map { index in
        var value = UInt32(index)
        for _ in 0 ..< 8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }
}

private nonisolated extension Data {
    // Zip is little-endian throughout.
    mutating func append(uint16 value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func append(uint32 value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
