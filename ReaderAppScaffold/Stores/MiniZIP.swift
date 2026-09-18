import Foundation
import Compression

// MARK: - 最小 ZIP 读取器

/// 极简 ZIP 解压（EPUB 容器专用）：只支持 store(0) 与 deflate(8) 两种压缩方式，
/// 覆盖留空目录项与 UTF-8 文件名标志。不需要任何第三方依赖——
/// deflate 交给系统 `Compression` 框架的 COMPRESSION_ZLIB。
enum MiniZIP {

    struct Entry {
        let name: String
        let data: Data
    }

    enum ZipError: LocalizedError {
        case notAZip
        case corrupt(String)

        var errorDescription: String? {
            switch self {
            case .notAZip: return "文件不是有效的 ZIP（EPUB）容器"
            case .corrupt(let detail): return "ZIP 解析失败：\(detail)"
            }
        }
    }

    /// 读取一个 ZIP 文件的所有条目。展开为 [String: Data]（以条目名为 key）。
    static func entries(in url: URL) throws -> [String: Data] {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ZipError.corrupt("无法读取文件") }
        return try entries(from: data)
    }

    static func entries(from data: Data) throws -> [String: Data] {
        guard data.count > 22 else { throw ZipError.notAZip }
        let bytes = [UInt8](data)

        // 1. 在文件尾部找 End Of Central Directory (PK\x05\x06)
        guard let eocd = findEOCD(bytes) else { throw ZipError.notAZip }
        let centralOffset = le32(bytes, eocd + 16)
        let centralCount = le16(bytes, eocd + 10)

        // 2. 遍历中央目录条目 (PK\x01\x02)
        var entries: [String: Data] = [:]
        var cursor = Int(centralOffset)
        for _ in 0..<centralCount {
            guard cursor + 46 <= bytes.count,
                  bytes[cursor] == 0x50, bytes[cursor + 1] == 0x4B,
                  bytes[cursor + 2] == 0x01, bytes[cursor + 3] == 0x02 else {
                throw ZipError.corrupt("中央目录损坏")
            }
            let method = le16(bytes, cursor + 10)
            let flags = le16(bytes, cursor + 8)
            let compressedSize = le32(bytes, cursor + 20)
            let uncompressedSize = le32(bytes, cursor + 24)
            let nameLen = le16(bytes, cursor + 28)
            let extraLen = le16(bytes, cursor + 30)
            let commentLen = le16(bytes, cursor + 32)
            let localOffset = le32(bytes, cursor + 42)

            let nameStart = cursor + 46
            let name = decodeName(bytes, nameStart, Int(nameLen), utf8Flag: (flags & 0x0800) != 0)

            // 3. 跳转本地文件头取数据
            if let local = readLocalEntry(bytes, localOffset: localOffset,
                                          compressedSize: Int(compressedSize),
                                          uncompressedSize: Int(uncompressedSize),
                                          method: method) {
                entries[name] = local
            }

            cursor = nameStart + Int(nameLen) + Int(extraLen) + Int(commentLen)
        }
        guard !entries.isEmpty else { throw ZipError.corrupt("没有任何文件条目") }
        return entries
    }

    // MARK: - 内部

    private static func findEOCD(_ bytes: [UInt8]) -> Int? {
        // 签名 0x06054b50，最少 22 字节，最多往前找 65557 字节
        let window = min(bytes.count, 65557)
        var i = bytes.count - window
        while i + 22 <= bytes.count {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4B,
               bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 {
                return i
            }
            i += 1
        }
        return nil
    }

    /// 根据中央目录偏移处的本地文件头取原始字节并解压。
    private static func readLocalEntry(
        _ bytes: [UInt8],
        localOffset: UInt32,
        compressedSize: Int,
        uncompressedSize: Int,
        method: UInt16
    ) -> Data? {
        let offset = Int(localOffset)
        guard offset + 30 <= bytes.count,
              bytes[offset] == 0x50, bytes[offset + 1] == 0x4B,
              bytes[offset + 2] == 0x03, bytes[offset + 3] == 0x04 else { return nil }
        let nameLen = le16(bytes, offset + 26)
        let extraLen = le16(bytes, offset + 28)
        let dataStart = offset + 30 + Int(nameLen) + Int(extraLen)
        guard dataStart + compressedSize <= bytes.count else { return nil }

        let raw = Data(bytes[dataStart..<(dataStart + compressedSize)])
        switch method {
        case 0: // stored
            return raw
        case 8: // deflate
            return inflate(raw, expectedSize: uncompressedSize)
        default:
            return nil
        }
    }

    private static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        guard !data.isEmpty else { return Data() }
        // 中央目录给出了准确的解压后大小：一次性解压到位，
        // 不需要流式推进（Compression 不暴露输入消费字节数，流式反而不可靠）。
        let capacity = max(expectedSize, 64)
        var dst = [UInt8](repeating: 0, count: capacity)
        let produced = data.withUnsafeBytes { raw -> Int in
            let src = raw.bindMemory(to: UInt8.self).baseAddress!
            return dst.withUnsafeMutableBytes { dptr -> Int in
                let dbase = dptr.bindMemory(to: UInt8.self).baseAddress!
                return compression_decode_buffer(dbase, capacity, src, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard produced > 0 else { return nil }
        return Data(dst.prefix(produced))
    }

    // MARK: - 字节读取

    private static func le16(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(b[o]) | (UInt16(b[o + 1]) << 8)
    }

    private static func le32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | (UInt32(b[o + 1]) << 8) | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
    }

    private static func decodeName(_ b: [UInt8], _ o: Int, _ len: Int, utf8Flag: Bool) -> String {
        guard len > 0 else { return "" }
        let slice = Array(b[o..<(o + len)])
        if utf8Flag, let s = String(bytes: slice, encoding: .utf8) {
            return s
        }
        // 非 UTF-8 标志或解码失败：按 Latin-1 兜底（中文场景极少见）
        if let s = String(bytes: slice, encoding: .isoLatin1) { return s }
        return String(bytes: slice, encoding: .utf8) ?? ""
    }
}