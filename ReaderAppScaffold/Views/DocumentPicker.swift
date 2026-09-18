import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - 系统文件选择器（UIKit 实现）

/// 直接在「当前最上层 UIViewController」上呈现系统文件选择器。
///
/// 为什么不继续用 SwiftUI 的 `.fileImporter`：
/// `.fileImporter` 依赖 SwiftUI 自己的呈现链。当发起它的视图**本身已经是以
/// sheet 呈现的页面**（本项目的「导入书源」「导入 TXT」两个面板都是 sheet）时，
/// 呈现链可能冲突，表现为点了按钮**什么都不发生**，既不报错也不弹窗——
/// 正是"完全没反应"的现象。`UIDocumentPickerViewController` 直接挂在
/// 视图控制器上呈现，绕开这条链路，稳定得多。
///
/// `asCopy: true` 让系统先把文件复制到 App 的临时目录再交付，
/// 拿到的是普通本地 URL，不依赖 security-scoped 授权是否成功。
enum FilePicker {

    enum PickerError: LocalizedError {
        case noPresenter
        case alreadyPresenting
        case cancelled

        var errorDescription: String? {
            switch self {
            case .noPresenter: return "找不到可用于弹出文件选择器的界面"
            case .alreadyPresenting: return "文件选择器已经打开了"
            case .cancelled: return "已取消"
            }
        }
    }

    /// 保留 delegate：UIDocumentPickerViewController 只弱引用 delegate，
    /// 不持有的话回调还没触发就被释放了。
    private static var retainedDelegate: PickerDelegate?

    @MainActor
    static func present(
        contentTypes: [UTType],
        allowsMultiple: Bool = false,
        completion: @escaping (Result<[URL], Error>) -> Void
    ) {
        guard let host = topViewController() else {
            completion(.failure(PickerError.noPresenter))
            return
        }
        // 已经有选择器在呈现时不要再叠一个（否则同样会静默失败）
        if host.presentedViewController is UIDocumentPickerViewController {
            completion(.failure(PickerError.alreadyPresenting))
            return
        }

        let delegate = PickerDelegate { result in
            retainedDelegate = nil
            completion(result)
        }
        retainedDelegate = delegate

        // asCopy: true → 系统复制一份到临时目录，避免安全作用域读取问题
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.allowsMultipleSelection = allowsMultiple
        picker.shouldShowFileExtensions = true
        picker.delegate = delegate
        host.present(picker, animated: true)
    }

    /// 沿着 导航/标签/模态 层级找到当前真正在最上面的视图控制器。
    @MainActor
    static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let root: UIViewController?
        if let base {
            root = base
        } else {
            root = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }?
                .rootViewController
        }
        guard let root else { return nil }

        if let nav = root as? UINavigationController {
            return topViewController(base: nav.visibleViewController ?? nav)
        }
        if let tab = root as? UITabBarController {
            return topViewController(base: tab.selectedViewController ?? tab)
        }
        if let presented = root.presentedViewController {
            return topViewController(base: presented)
        }
        return root
    }

    private final class PickerDelegate: NSObject, UIDocumentPickerDelegate {
        private let completion: (Result<[URL], Error>) -> Void

        init(completion: @escaping (Result<[URL], Error>) -> Void) {
            self.completion = completion
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            completion(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion(.failure(PickerError.cancelled))
        }
    }
}

// MARK: - 统一的文件读取与解码

/// 读取文件内容：FileCoordinator 优先（iCloud / 第三方 provider 的未下载或
/// 正在同步文件更可靠），失败再退回直接读取。失败时带上具体原因。
enum FileTextReader {

    enum ReadError: LocalizedError {
        case unreadable(String)
        case empty
        case unknownEncoding

        var errorDescription: String? {
            switch self {
            case .unreadable(let detail): return "无法读取文件：\(detail)"
            case .empty: return "文件是空的，没有可导入的内容"
            case .unknownEncoding: return "文件编码无法识别（试过 UTF-8 / UTF-16 / GB18030）"
            }
        }
    }

    /// 读取并解码为字符串。调用方负责 security-scoped 的 start/stop（如需）。
    static func readText(from url: URL) throws -> String {
        let data = try readData(from: url)
        guard !data.isEmpty else { throw ReadError.empty }
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .utf16) { return s }
        let cf = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        if let s = String(data: data, encoding: String.Encoding(rawValue: cf)) { return s }
        throw ReadError.unknownEncoding
    }

    static func readData(from url: URL) throws -> Data {
        var data: Data?
        var failure: Error?

        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            do { data = try Data(contentsOf: readURL) } catch { failure = error }
        }
        if data == nil, let coordinatorError { failure = coordinatorError }
        if data == nil {
            do { data = try Data(contentsOf: url) } catch { failure = failure ?? error }
        }

        guard let data else {
            throw ReadError.unreadable(failure?.localizedDescription ?? "未知错误")
        }
        return data
    }
}
