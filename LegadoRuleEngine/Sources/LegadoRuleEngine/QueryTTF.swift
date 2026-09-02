import Foundation

/// 对应 legado: model/analyzeRule/QueryTTF.java
/// 解析 TTF 字体二进制数据，建立 Unicode <-> 字形轮廓 的映射表，用于破解书源正文里
/// "自定义字体反爬"（网站给每章甚至每次请求生成一份 Unicode 编码打乱的专属字体，
/// 真实文字要通过对比字形轮廓形状才能还原）。
///
/// 参考: <https://learn.microsoft.com/zh-cn/typography/opentype/spec/otff>
///
/// ⚠️ 精度风险提示：`getGlyfById` 对"复合字形"（如带部首拼接、变体字）会把浮点缩放值
/// (xScale/yScale等) 拼进结果字符串。Java 的 `Float.toString()` 和 Swift 的
/// 字符串插值在极少数边界精度上可能给出不同的十进制表示，如果你要对接**别人用
/// legado/Java 版生成的字形特征库**做字符串精确匹配，复合字形这部分键可能对不上
/// （简单字形——绝大多数汉字走的都是这条路径——用的是纯整数坐标拼接，不受影响）。
/// 自己起服务端重新生成特征库、或只处理简单字形的场景不受此影响。
public final class QueryTTF {

    // MARK: - 内部数据结构（对应各 Layout/Record 内部类）

    private struct Header {
        var sfntVersion: UInt32 = 0
        var numTables: Int = 0
        var searchRange: Int = 0
        var entrySelector: Int = 0
        var rangeShift: Int = 0
    }

    private struct Directory {
        var tableTag: String = ""
        var checkSum: Int32 = 0
        var offset: Int = 0
        var length: Int = 0
    }

    private struct NameRecord {
        var platformID = 0, encodingID = 0, languageID = 0, nameID = 0, length = 0, offset = 0
    }

    private struct NameLayout {
        var format = 0, count = 0, stringOffset = 0
        var records: [NameRecord] = []
    }

    private struct HeadLayout {
        var majorVersion = 0, minorVersion = 0
        var fontRevision: Int32 = 0, checkSumAdjustment: Int32 = 0, magicNumber: Int32 = 0
        var flags = 0, unitsPerEm = 0
        var created: UInt64 = 0, modified: UInt64 = 0
        var xMin: Int16 = 0, yMin: Int16 = 0, xMax: Int16 = 0, yMax: Int16 = 0
        var macStyle = 0, lowestRecPPEM = 0
        var fontDirectionHint: Int16 = 0
        var indexToLocFormat: Int16 = 0
        var glyphDataFormat: Int16 = 0
    }

    private struct MaxpLayout {
        var version: Int32 = 0
        var numGlyphs = 0
        var maxPoints = 0, maxContours = 0
        var maxCompositePoints = 0, maxCompositeContours = 0
        var maxZones = 0, maxTwilightPoints = 0, maxStorage = 0
        var maxFunctionDefs = 0, maxInstructionDefs = 0, maxStackElements = 0
        var maxSizeOfInstructions = 0, maxComponentElements = 0, maxComponentDepth = 0
    }

    private struct CmapRecord {
        var platformID = 0, encodingID = 0, offset = 0
    }

    private struct CmapFormat {
        var format = 0, length = 0, language = 0
        var segCountX2 = 0, searchRange = 0, entrySelector = 0, rangeShift = 0
        var endCode: [Int] = []
        var reservedPad = 0
        var startCode: [Int] = []
        var idDelta: [Int] = []
        var idRangeOffsets: [Int] = []
        var firstCode = 0, entryCount = 0
        var glyphIdArray: [Int] = []
    }

    private struct CmapLayout {
        var version = 0, numTables = 0
        var records: [CmapRecord] = []
        var tables: [Int: CmapFormat] = [:]
    }

    private struct GlyphTableBySimple {
        var endPtsOfContours: [Int] = []
        var instructionLength = 0
        var instructions: [Int] = []
        var flags: [Int] = []
        var xCoordinates: [Int] = []
        var yCoordinates: [Int] = []
    }

    private struct GlyphTableComponent {
        var flags = 0
        var glyphIndex = 0
        var argument1 = 0
        var argument2 = 0
        var xScale: Float = 0, scale01: Float = 0, scale10: Float = 0, yScale: Float = 0
    }

    private struct GlyfLayout {
        var numberOfContours: Int16 = 0
        var xMin: Int16 = 0, yMin: Int16 = 0, xMax: Int16 = 0, yMax: Int16 = 0
        var glyphSimple: GlyphTableBySimple?
        var glyphComponent: [GlyphTableComponent]?
    }

    // MARK: - 字节读取器（大端序，对齐 Java 的 ByteBuffer.order(BIG_ENDIAN)）

    private final class BufferReader {
        private let buffer: [UInt8]
        private var pos: Int

        init(_ buffer: [UInt8], _ index: Int) {
            self.buffer = buffer
            self.pos = index
        }

        func position(_ index: Int) { pos = index }
        func position() -> Int { pos }

        private func take(_ n: Int) -> [UInt8] {
            guard pos >= 0, pos + n <= buffer.count else {
                pos += n
                return [UInt8](repeating: 0, count: n)
            }
            let slice = Array(buffer[pos..<pos + n])
            pos += n
            return slice
        }

        func readUInt64() -> UInt64 {
            let b = take(8)
            var v: UInt64 = 0
            for byte in b { v = (v << 8) | UInt64(byte) }
            return v
        }

        func readUInt32() -> UInt32 {
            let b = take(4)
            var v: UInt32 = 0
            for byte in b { v = (v << 8) | UInt32(byte) }
            return v
        }

        func readInt32() -> Int32 { Int32(bitPattern: readUInt32()) }

        func readUInt16() -> Int {
            let b = take(2)
            return (Int(b[0]) << 8) | Int(b[1])
        }

        func readInt16() -> Int16 {
            let v = readUInt16()
            return Int16(bitPattern: UInt16(v))
        }

        func readUInt8() -> Int {
            let b = take(1)
            return Int(b[0])
        }

        func readInt8() -> Int8 {
            let b = take(1)
            return Int8(bitPattern: b[0])
        }

        func readByteArray(_ len: Int) -> [UInt8] { take(len) }

        func readUInt8Array(_ len: Int) -> [Int] {
            (0..<len).map { _ in readUInt8() }
        }

        func readInt16Array(_ len: Int) -> [Int] {
            (0..<len).map { _ in Int(readInt16()) }
        }

        func readUInt16Array(_ len: Int) -> [Int] {
            (0..<len).map { _ in readUInt16() }
        }

        func readInt32Array(_ len: Int) -> [Int] {
            (0..<len).map { _ in Int(readInt32()) }
        }
    }

    // MARK: - 状态

    private var fileHeader = Header()
    private var directorys: [String: Directory] = [:]
    private var name = NameLayout()
    private var head = HeadLayout()
    private var maxp = MaxpLayout()
    private var cmap = CmapLayout()
    private var loca: [Int] = []
    private var glyfArray: [GlyfLayout?] = []

    /// Unicode -> 字形轮廓字符串
    public private(set) var unicodeToGlyph: [Int: String] = [:]
    /// 字形轮廓字符串 -> Unicode（反查）
    public private(set) var glyphToUnicode: [String: Int] = [:]
    /// Unicode -> 轮廓索引(glyfId)
    public private(set) var unicodeToGlyphId: [Int: Int] = [:]

    // MARK: - 建表

    private func readNameTable(_ buffer: [UInt8]) {
        guard let dataTable = directorys["name"] else { return }
        let reader = BufferReader(buffer, dataTable.offset)
        name.format = reader.readUInt16()
        name.count = reader.readUInt16()
        name.stringOffset = reader.readUInt16()
        for _ in 0..<name.count {
            var record = NameRecord()
            record.platformID = reader.readUInt16()
            record.encodingID = reader.readUInt16()
            record.languageID = reader.readUInt16()
            record.nameID = reader.readUInt16()
            record.length = reader.readUInt16()
            record.offset = reader.readUInt16()
            name.records.append(record)
        }
    }

    private func readHeadTable(_ buffer: [UInt8]) {
        guard let dataTable = directorys["head"] else { return }
        let reader = BufferReader(buffer, dataTable.offset)
        head.majorVersion = reader.readUInt16()
        head.minorVersion = reader.readUInt16()
        head.fontRevision = reader.readInt32()
        head.checkSumAdjustment = reader.readInt32()
        head.magicNumber = reader.readInt32()
        head.flags = reader.readUInt16()
        head.unitsPerEm = reader.readUInt16()
        head.created = reader.readUInt64()
        head.modified = reader.readUInt64()
        head.xMin = reader.readInt16()
        head.yMin = reader.readInt16()
        head.xMax = reader.readInt16()
        head.yMax = reader.readInt16()
        head.macStyle = reader.readUInt16()
        head.lowestRecPPEM = reader.readUInt16()
        head.fontDirectionHint = reader.readInt16()
        head.indexToLocFormat = reader.readInt16()
        head.glyphDataFormat = reader.readInt16()
    }

    private func readLocaTable(_ buffer: [UInt8]) {
        guard let dataTable = directorys["loca"] else { return }
        let reader = BufferReader(buffer, dataTable.offset)
        if head.indexToLocFormat == 0 {
            loca = reader.readUInt16Array(dataTable.length / 2)
            for i in loca.indices { loca[i] *= 2 }
        } else {
            loca = reader.readInt32Array(dataTable.length / 4)
        }
    }

    private func readCmapTable(_ buffer: [UInt8]) {
        guard let dataTable = directorys["cmap"] else { return }
        let reader = BufferReader(buffer, dataTable.offset)
        cmap.version = reader.readUInt16()
        cmap.numTables = reader.readUInt16()
        for _ in 0..<cmap.numTables {
            var record = CmapRecord()
            record.platformID = reader.readUInt16()
            record.encodingID = reader.readUInt16()
            record.offset = Int(reader.readUInt32())
            cmap.records.append(record)
        }

        for formatTable in cmap.records {
            let fmtOffset = formatTable.offset
            if cmap.tables[fmtOffset] != nil { continue }
            reader.position(dataTable.offset + fmtOffset)

            var f = CmapFormat()
            f.format = reader.readUInt16()
            f.length = reader.readUInt16()
            f.language = reader.readUInt16()

            switch f.format {
            case 0:
                f.glyphIdArray = reader.readUInt8Array(max(0, f.length - 6))
                for unicode in f.glyphIdArray.indices {
                    if f.glyphIdArray[unicode] == 0 { continue } // 排除轮廓索引为0的Unicode
                    unicodeToGlyphId[unicode] = f.glyphIdArray[unicode]
                }
            case 4:
                f.segCountX2 = reader.readUInt16()
                let segCount = f.segCountX2 / 2
                f.searchRange = reader.readUInt16()
                f.entrySelector = reader.readUInt16()
                f.rangeShift = reader.readUInt16()
                f.endCode = reader.readUInt16Array(segCount)
                f.reservedPad = reader.readUInt16()
                f.startCode = reader.readUInt16Array(segCount)
                f.idDelta = reader.readInt16Array(segCount)
                f.idRangeOffsets = reader.readUInt16Array(segCount)
                let glyphIdArrayLength = (f.length - 16 - (segCount * 8)) / 2
                f.glyphIdArray = reader.readUInt16Array(max(0, glyphIdArrayLength))

                for segmentIndex in 0..<segCount {
                    let unicodeInclusive = f.startCode[segmentIndex]
                    let unicodeExclusive = f.endCode[segmentIndex]
                    let idDelta = f.idDelta[segmentIndex]
                    let idRangeOffset = f.idRangeOffsets[segmentIndex]
                    guard unicodeInclusive <= unicodeExclusive else { continue }
                    for unicode in unicodeInclusive...unicodeExclusive {
                        var glyphId = 0
                        if idRangeOffset == 0 {
                            glyphId = (unicode + idDelta) & 0xFFFF
                        } else {
                            let gIndex = (idRangeOffset / 2) + unicode - unicodeInclusive + segmentIndex - segCount
                            if gIndex >= 0, gIndex < glyphIdArrayLength {
                                glyphId = f.glyphIdArray[gIndex] + idDelta
                            }
                        }
                        if glyphId == 0 { continue }
                        unicodeToGlyphId[unicode] = glyphId
                    }
                }
            case 6:
                f.firstCode = reader.readUInt16()
                f.entryCount = reader.readUInt16()
                f.glyphIdArray = reader.readUInt16Array(f.entryCount)
                var unicodeIndex = f.firstCode
                for gIndex in 0..<f.entryCount {
                    unicodeToGlyphId[unicodeIndex] = f.glyphIdArray[gIndex]
                    unicodeIndex += 1
                }
            default:
                break
            }
            cmap.tables[fmtOffset] = f
        }
    }

    private func readMaxpTable(_ buffer: [UInt8]) {
        guard let dataTable = directorys["maxp"] else { return }
        let reader = BufferReader(buffer, dataTable.offset)
        maxp.version = reader.readInt32()
        maxp.numGlyphs = reader.readUInt16()
        maxp.maxPoints = reader.readUInt16()
        maxp.maxContours = reader.readUInt16()
        maxp.maxCompositePoints = reader.readUInt16()
        maxp.maxCompositeContours = reader.readUInt16()
        maxp.maxZones = reader.readUInt16()
        maxp.maxTwilightPoints = reader.readUInt16()
        maxp.maxStorage = reader.readUInt16()
        maxp.maxFunctionDefs = reader.readUInt16()
        maxp.maxInstructionDefs = reader.readUInt16()
        maxp.maxStackElements = reader.readUInt16()
        maxp.maxSizeOfInstructions = reader.readUInt16()
        maxp.maxComponentElements = reader.readUInt16()
        maxp.maxComponentDepth = reader.readUInt16()
    }

    private func readGlyfTable(_ buffer: [UInt8]) {
        guard let dataTable = directorys["glyf"] else { return }
        let glyfCount = maxp.numGlyphs
        glyfArray = [GlyfLayout?](repeating: nil, count: glyfCount)

        let reader = BufferReader(buffer, 0)
        for index in 0..<glyfCount {
            guard index + 1 < loca.count else { continue }
            if loca[index] == loca[index + 1] { continue } // 字形不存在
            let offset = dataTable.offset + loca[index]
            var glyph = GlyfLayout()
            reader.position(offset)
            glyph.numberOfContours = reader.readInt16()
            if Int(glyph.numberOfContours) > maxp.maxContours { continue } // 无效字形
            glyph.xMin = reader.readInt16()
            glyph.yMin = reader.readInt16()
            glyph.xMax = reader.readInt16()
            glyph.yMax = reader.readInt16()

            if glyph.numberOfContours == 0 { continue }

            if glyph.numberOfContours > 0 {
                // 简单字形
                var simple = GlyphTableBySimple()
                simple.endPtsOfContours = reader.readUInt16Array(Int(glyph.numberOfContours))
                simple.instructionLength = reader.readUInt16()
                simple.instructions = reader.readUInt8Array(simple.instructionLength)

                guard let lastPt = simple.endPtsOfContours.last else { continue }
                let flagLength = lastPt + 1
                var flags = [Int](repeating: 0, count: flagLength)
                var n = 0
                while n < flagLength {
                    let glyphSimpleFlag = reader.readUInt8()
                    flags[n] = glyphSimpleFlag
                    if (glyphSimpleFlag & 0x08) == 0x08 {
                        var m = reader.readUInt8()
                        while m > 0 {
                            n += 1
                            if n < flagLength { flags[n] = glyphSimpleFlag }
                            m -= 1
                        }
                    }
                    n += 1
                }
                simple.flags = flags

                var xCoordinates = [Int](repeating: 0, count: flagLength)
                for i in 0..<flagLength {
                    switch flags[i] & 0x12 {
                    case 0x02: xCoordinates[i] = -1 * reader.readUInt8()
                    case 0x12: xCoordinates[i] = reader.readUInt8()
                    case 0x10: xCoordinates[i] = 0
                    case 0x00: xCoordinates[i] = Int(reader.readInt16())
                    default: break
                    }
                }
                simple.xCoordinates = xCoordinates

                var yCoordinates = [Int](repeating: 0, count: flagLength)
                for i in 0..<flagLength {
                    switch flags[i] & 0x24 {
                    case 0x04: yCoordinates[i] = -1 * reader.readUInt8()
                    case 0x24: yCoordinates[i] = reader.readUInt8()
                    case 0x20: yCoordinates[i] = 0
                    case 0x00: yCoordinates[i] = Int(reader.readInt16())
                    default: break
                    }
                }
                simple.yCoordinates = yCoordinates
                glyph.glyphSimple = simple
            } else {
                // 复合字形
                var components: [GlyphTableComponent] = []
                while true {
                    var comp = GlyphTableComponent()
                    comp.flags = reader.readUInt16()
                    comp.glyphIndex = reader.readUInt16()
                    switch comp.flags & 0b11 {
                    case 0b00:
                        comp.argument1 = reader.readUInt8()
                        comp.argument2 = reader.readUInt8()
                    case 0b10:
                        comp.argument1 = Int(reader.readInt8())
                        comp.argument2 = Int(reader.readInt8())
                    case 0b01:
                        comp.argument1 = reader.readUInt16()
                        comp.argument2 = reader.readUInt16()
                    case 0b11:
                        comp.argument1 = Int(reader.readInt16())
                        comp.argument2 = Int(reader.readInt16())
                    default: break
                    }
                    switch comp.flags & 0b11001000 {
                    case 0b00001000:
                        let s = Float(reader.readUInt16()) / 16384.0
                        comp.xScale = s
                        comp.yScale = s
                    case 0b01000000:
                        comp.xScale = Float(reader.readUInt16()) / 16384.0
                        comp.yScale = Float(reader.readUInt16()) / 16384.0
                    case 0b10000000:
                        comp.xScale = Float(reader.readUInt16()) / 16384.0
                        comp.scale01 = Float(reader.readUInt16()) / 16384.0
                        comp.scale10 = Float(reader.readUInt16()) / 16384.0
                        comp.yScale = Float(reader.readUInt16()) / 16384.0
                    default: break
                    }
                    components.append(comp)
                    if (comp.flags & 0x20) == 0 { break }
                }
                glyph.glyphComponent = components
            }
            glyfArray[index] = glyph
        }
    }

    /// 使用轮廓索引值获取轮廓数据（简单字形返回 "x,y|x,y|..." 坐标串；复合字形返回 "[{...},...]"）
    public func getGlyfById(_ glyfId: Int) -> String? {
        guard glyfId >= 0, glyfId < glyfArray.count, let glyph = glyfArray[glyfId] else { return nil }
        if glyph.numberOfContours >= 0 {
            guard let simple = glyph.glyphSimple else { return nil }
            let parts = (0..<simple.flags.count).map { i in
                "\(simple.xCoordinates[i]),\(simple.yCoordinates[i])"
            }
            return parts.joined(separator: "|")
        } else {
            let parts = (glyph.glyphComponent ?? []).map { g in
                "{flags:\(g.flags),glyphIndex:\(g.glyphIndex),arg1:\(g.argument1),arg2:\(g.argument2),"
                    + "xScale:\(g.xScale),scale01:\(g.scale01),scale10:\(g.scale10),yScale:\(g.yScale)}"
            }
            return "[" + parts.joined(separator: ",") + "]"
        }
    }

    /// 使用 Unicode 值查询轮廓索引，找不到返回 0（对应"丢失的字符"）
    public func getGlyfIdByUnicode(_ unicode: Int) -> Int {
        unicodeToGlyphId[unicode] ?? 0
    }

    /// 使用 Unicode 值查询轮廓数据
    public func getGlyfByUnicode(_ unicode: Int) -> String? {
        unicodeToGlyph[unicode]
    }

    /// 使用轮廓数据反查 Unicode 值，找不到返回 0
    public func getUnicodeByGlyf(_ glyph: String) -> Int {
        glyphToUnicode[glyph] ?? 0
    }

    /// 是否是空白类 Unicode 字符
    public func isBlankUnicode(_ unicode: Int) -> Bool {
        switch unicode {
        case 0x0009, 0x0020, 0x00A0, 0x2002, 0x2003, 0x2007,
             0x200A, 0x200B, 0x200C, 0x200D, 0x202F, 0x205F:
            return true
        default:
            return false
        }
    }

    // MARK: - 构造

    public convenience init(_ buffer: Data) {
        self.init([UInt8](buffer))
    }

    public init(_ buffer: [UInt8]) {
        let fontReader = BufferReader(buffer, 0)
        fileHeader.sfntVersion = fontReader.readUInt32()
        fileHeader.numTables = fontReader.readUInt16()
        fileHeader.searchRange = fontReader.readUInt16()
        fileHeader.entrySelector = fontReader.readUInt16()
        fileHeader.rangeShift = fontReader.readUInt16()

        for _ in 0..<fileHeader.numTables {
            var d = Directory()
            d.tableTag = String(bytes: fontReader.readByteArray(4), encoding: .ascii) ?? ""
            d.checkSum = fontReader.readInt32()
            d.offset = Int(fontReader.readUInt32())
            d.length = Int(fontReader.readUInt32())
            directorys[d.tableTag] = d
        }

        readNameTable(buffer)
        readHeadTable(buffer)
        readCmapTable(buffer)
        readLocaTable(buffer)
        readMaxpTable(buffer)
        readGlyfTable(buffer)

        let glyfArrayLength = glyfArray.count
        for (key, val) in unicodeToGlyphId {
            if val >= glyfArrayLength { continue }
            guard let glyfString = getGlyfById(val) else {
                unicodeToGlyph[key] = nil
                continue
            }
            unicodeToGlyph[key] = glyfString
            glyphToUnicode[glyfString] = key
        }
    }
}
