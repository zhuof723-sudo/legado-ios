import Foundation
import JavaScriptCore
import CommonCrypto

/// 一批和"哪个规则在跑"无关、纯工具性质的 java.* 方法实现，AnalyzeRule 和 AnalyzeUrl
/// 各自的 JS 桥接类（LegadoJSBridge / AnalyzeUrlJSBridge）都会用到，抽出来共用一份实现。
public enum JSCommonMethods {
    /// 供 java.getWebViewUA() 用；没有配置的话给一个说得过去的默认值。
    /// 需要更贴近真实设备的UA就在App启动时改这个。
    public static var defaultUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"

    /// 供 java.androidId()/deviceID() 用；iOS 没有这两个概念的直接对应物，
    /// 默认给个每次启动都一样的稳定占位符即可（大多数书源只是拿它当"设备指纹"参与请求签名，
    /// 不要求是真实设备标识）。需要更真实的设备区分度可以在App里换成 identifierForVendor。
    public static var deviceIdentifier = "ios-device"

    public static func base64Encode(_ s: String) -> String {
        Data(s.utf8).base64EncodedString()
    }

    public static func base64Decode(_ s: String) -> String {
        guard let data = Data(base64Encoded: s) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    public static func base64DecodeToByteArray(_ s: String) -> [Int] {
        guard let data = Data(base64Encoded: s) else { return [] }
        return data.map { Int($0) }
    }

    public static func hexDecodeToString(_ hex: String) -> String {
        guard let data = dataFromHex(hex) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    public static func dataFromHex(_ hex: String) -> Data? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count % 2 != 0 { cleaned = "0" + cleaned }
        var data = Data()
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    /// 对应 java.timeFormat(millis)，默认输出 "yyyy-MM-dd HH:mm:ss"
    public static func timeFormat(_ millis: Double) -> String {
        let date = Date(timeIntervalSince1970: millis / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    // MARK: - 常用 java.* 工具

    public static func encodeURI(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    public static func encodeURIComponent(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    public static func decodeURI(_ s: String) -> String {
        s.removingPercentEncoding ?? s
    }

    /// HTML → 纯文本（去标签 + 常见实体解码），对应 java.htmlFormat
    public static func htmlFormat(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression])
        t = t.replacingOccurrences(of: "</p>", with: "\n", options: [.regularExpression])
        t = t.replacingOccurrences(of: "<[^>]+>", with: "", options: [.regularExpression])
        let entities: [String: String] = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'"
        ]
        for (k, v) in entities { t = t.replacingOccurrences(of: k, with: v) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// MD5 摘要（小写 hex），对应 java.md5Encode
    public static func md5Encode(_ s: String) -> String {
        let data = Data(s.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buf in
            _ = CC_MD5(buf.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 随机 UUID，对应 java.randomUUID
    public static func randomUUID() -> String {
        UUID().uuidString
    }

    /// 中文数字章节名 → 阿拉伯数字（第一百二十三章 → 第123章），对应 java.toNumChapter
    public static func toNumChapter(_ s: String) -> String {
        let cn: [Character: Int] = ["零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
                                    "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let units: [Character: Int] = ["十": 10, "百": 100, "千": 1000, "万": 10000]
        var out = ""
        var i = 0
        let chars = Array(s)
        while i < chars.count {
            let c = chars[i]
            if cn[c] != nil {
                var total = 0, section = 0
                var j = i
                while j < chars.count {
                    let cc = chars[j]
                    if let d = cn[cc] {
                        section = section * 10 + d
                    } else if let u = units[cc] {
                        if section == 0 { section = 1 }
                        if u == 10000 { total = (total + section) * 10000; section = 0 }
                        else { total += section * u; section = 0 }
                    } else { break }
                    j += 1
                }
                total += section
                out += "\(total)"
                i = j
            } else {
                out.append(c)
                i += 1
            }
        }
        return out
    }
}

// MARK: - java.createSymmetricCrypto(transformation, key, iv)

/// 对应 `java.createSymmetricCrypto("AES/CBC/PKCS5Padding", key, iv)` 这类调用，
/// 返回一个支持 encrypt/decrypt/encryptBase64/decryptStr 的对象。
/// 支持 AES / DES / 3DES，CBC/ECB 模式，PKCS7(=PKCS5)填充或不填充。
@objc public protocol SymmetricCryptoJSBridgeExport: JSExport {
    func encrypt(_ data: [Int]) -> [Int]
    func decrypt(_ data: [Int]) -> [Int]
    func encryptBase64(_ data: String) -> String
    /// 入参可以是字节数组，也可以是base64字符串（书源里两种写法都有人用），自动识别
    func decryptStr(_ data: JSValue) -> String
}

@objc public final class SymmetricCryptoJSBridge: NSObject, SymmetricCryptoJSBridgeExport {
    private let algorithm: CCAlgorithm
    private let keyData: Data
    private let ivData: Data
    private let options: CCOptions
    private let isECB: Bool

    init?(transformation: String, key: String, iv: String) {
        let parts = transformation.uppercased().split(separator: "/").map(String.init)
        guard let algoName = parts.first else { return nil }
        switch algoName {
        case "AES": algorithm = CCAlgorithm(kCCAlgorithmAES)
        case "DES": algorithm = CCAlgorithm(kCCAlgorithmDES)
        case "3DES", "DESEDE", "TRIPLEDES": algorithm = CCAlgorithm(kCCAlgorithm3DES)
        default: return nil
        }
        isECB = parts.count > 1 && parts[1] == "ECB"
        let noPadding = transformation.uppercased().contains("NOPADDING")
        options = noPadding ? CCOptions(0) : CCOptions(kCCOptionPKCS7Padding)
        keyData = Data(key.utf8)
        ivData = Data(iv.utf8)
    }

    private func crypt(_ input: Data, encrypt: Bool) -> Data? {
        let blockSize = algorithm == CCAlgorithm(kCCAlgorithmAES) ? kCCBlockSizeAES128 : kCCBlockSizeDES
        var outLength = 0
        var outBuffer = [UInt8](repeating: 0, count: input.count + blockSize)
        var status: CCCryptorStatus = CCCryptorStatus(kCCSuccess)

        outBuffer.withUnsafeMutableBytes { outPtr in
            keyData.withUnsafeBytes { keyPtr in
                input.withUnsafeBytes { inPtr in
                    if isECB {
                        status = CCCrypt(
                            CCOperation(encrypt ? kCCEncrypt : kCCDecrypt),
                            algorithm, options,
                            keyPtr.baseAddress, keyData.count,
                            nil,
                            inPtr.baseAddress, input.count,
                            outPtr.baseAddress, outPtr.count,
                            &outLength
                        )
                    } else {
                        ivData.withUnsafeBytes { ivPtr in
                            status = CCCrypt(
                                CCOperation(encrypt ? kCCEncrypt : kCCDecrypt),
                                algorithm, options,
                                keyPtr.baseAddress, keyData.count,
                                ivPtr.baseAddress,
                                inPtr.baseAddress, input.count,
                                outPtr.baseAddress, outPtr.count,
                                &outLength
                            )
                        }
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return Data(outBuffer.prefix(outLength))
    }

    public func encrypt(_ data: [Int]) -> [Int] {
        let input = Data(data.map { UInt8(truncatingIfNeeded: $0) })
        guard let out = crypt(input, encrypt: true) else { return [] }
        return out.map { Int($0) }
    }

    public func decrypt(_ data: [Int]) -> [Int] {
        let input = Data(data.map { UInt8(truncatingIfNeeded: $0) })
        guard let out = crypt(input, encrypt: false) else { return [] }
        return out.map { Int($0) }
    }

    public func encryptBase64(_ data: String) -> String {
        guard let out = crypt(Data(data.utf8), encrypt: true) else { return "" }
        return out.base64EncodedString()
    }

    public func decryptStr(_ data: JSValue) -> String {
        var input: Data?
        if data.isString, let s = data.toString() {
            input = Data(base64Encoded: s) ?? Data(s.utf8)
        } else if data.isArray, let arr = data.toArray() as? [Int] {
            input = Data(arr.map { UInt8(truncatingIfNeeded: $0) })
        }
        guard let inputData = input, let out = crypt(inputData, encrypt: false) else { return "" }
        return String(data: out, encoding: .utf8) ?? out.base64EncodedString()
    }
}
