import Foundation

/// A zip of stored (uncompressed) entries, as a Word file is: no library, no compression, and fixed timestamps, so the
/// same parts make the same bytes.
struct QuillZip {
    private var entries: [(name: String, data: Data)] = []

    mutating func add(_ name: String, _ data: Data) { entries.append((name, data)) }
    mutating func add(_ name: String, _ text: String) { add(name, Data(text.utf8)) }

    /// 1980-01-01 00:00, the earliest time a zip can say.
    private static let time: UInt16 = 0
    private static let date: UInt16 = (0 << 9) | (1 << 5) | 1

    var data: Data {
        var out = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = Self.crc32(entry.data)
            let offset = UInt32(out.count)
            // Local header.
            out.append(le32: 0x04034b50); out.append(le16: 20); out.append(le16: 0x0800); out.append(le16: 0)
            out.append(le16: Self.time); out.append(le16: Self.date)
            out.append(le32: crc); out.append(le32: UInt32(entry.data.count)); out.append(le32: UInt32(entry.data.count))
            out.append(le16: UInt16(name.count)); out.append(le16: 0)
            out.append(name); out.append(entry.data)
            // Its central directory record.
            central.append(le32: 0x02014b50); central.append(le16: 20); central.append(le16: 20); central.append(le16: 0x0800); central.append(le16: 0)
            central.append(le16: Self.time); central.append(le16: Self.date)
            central.append(le32: crc); central.append(le32: UInt32(entry.data.count)); central.append(le32: UInt32(entry.data.count))
            central.append(le16: UInt16(name.count)); central.append(le16: 0); central.append(le16: 0)
            central.append(le16: 0); central.append(le16: 0); central.append(le32: 0); central.append(le32: offset)
            central.append(name)
        }
        let start = UInt32(out.count)
        out.append(central)
        out.append(le32: 0x06054b50); out.append(le16: 0); out.append(le16: 0)
        out.append(le16: UInt16(entries.count)); out.append(le16: UInt16(entries.count))
        out.append(le32: UInt32(central.count)); out.append(le32: start); out.append(le16: 0)
        return out
    }

    private static let table: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
    mutating func append(le32 value: UInt32) { Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) } }
}
