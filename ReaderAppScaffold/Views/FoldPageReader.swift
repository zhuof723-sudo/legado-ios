import UIKit
import LegadoRuleEngine

/// 仿真翻页引擎：按参考截图复刻 legado 风格的整页翻折。
///
/// - 翻起的页是刚性折页，绕左缘做带透视的 Y 轴旋转；
/// - 正面显示当前页快照；翻过中线后露出背面（当前页镜像 + 淡灰罩）；
/// - 折痕处一条锐利窄阴影，折页根部叠一条柔和宽阴影；
/// - 底页在折痕右侧有渗出的纵向辉光，折页尖端拖出暗色爪影。
/// 交互：跟手翻页、松手按速度/进度回弹或完成、点击边缘程序化翻页。
///
/// 角度约定：angle ∈ [0, π]。
/// - 前进（折走当前页）：π = 全平盖住 → 0 = 完全折走露出下一页；
/// - 后退（上一页折回来）：0 = 折页竖直不可见 → π = 全平盖住显示上一页。
final class FoldPageReader: UIViewController, PageReaderContainer, UIGestureRecognizerDelegate {
    var pages: [String] = []
    let config: ReaderConfig
    var currentIndex: Int = 0
    var onPageChanged: ((Int) -> Void)?
    var reviewEnabled: Bool = false
    var onReviewTap: ((Int) -> Void)?
    var reviewCounts: [Int: Int] = [:]
    var inlineReviewMarkers: [InlineReviewMarker] = []
    var onInlineReviewTap: ((Int) -> Void)?
    var onOutsideTap: ((CGPoint) -> Void)?

    // MARK: 层级（自下而上）

    /// 当前页（静止的呈现层）。
    private var currentPageView: PageContentView?
    /// 底页：前进时是下一页，后退时是上一页。
    private var backPage: PageContentView?
    /// 折页扫过的空白区暗化。
    private let emptyShade = CAGradientLayer()
    /// 底页辉光（折痕右侧渗光）。
    private let glow = CAGradientLayer()
    /// 折痕锐利窄阴影（贴在底页上）。
    private let crease = CAGradientLayer()
    /// 折页根部投下的柔和宽阴影。
    private let rootShade = CAGradientLayer()
    /// 爪影：折页尖端拖出的暗楔形。
    private let claw = CAShapeLayer()
    /// 折页背面：镜像快照 + 淡灰罩。
    private let foldBack = UIView()
    /// 折页正面：当前页（或后退时的目标页）快照。
    private let foldFront = UIView()
    /// 折页上的柔和阴影（铺在 foldFront 内部，随旋转）。
    private let foldShade = CAGradientLayer()

    // MARK: 状态

    /// 翻页方向：1 前进（折当前页），-1 后退（上一页折回来）。
    private var direction = 1
    /// 本次折页完成后的目标页码。
    private var targetIndex = 0
    private var interactive = false
    private var isAnimating = false
    private var angle: CGFloat = .pi
    private var panStartX: CGFloat = 0

    init(pages: [String], config: ReaderConfig, initialIndex: Int) {
        self.pages = pages
        self.config = config
        self.currentIndex = initialIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(config.currentTheme.background)
        view.clipsToBounds = true
        setupShadowLayers()
        installPanGesture()
        if !pages.isEmpty {
            installPage(at: min(max(currentIndex, 0), pages.count - 1))
        }
    }

    // MARK: - 阴影层搭建（先挂到最底层，startFold 时再提到底页之上）

    private func setupShadowLayers() {
        emptyShade.colors = [
            UIColor.black.withAlphaComponent(0.26).cgColor,
            UIColor.black.withAlphaComponent(0).cgColor
        ]
        emptyShade.startPoint = CGPoint(x: 0, y: 0.5)
        emptyShade.endPoint = CGPoint(x: 1, y: 0.5)

        glow.colors = [
            UIColor.white.withAlphaComponent(0).cgColor,
            UIColor.white.withAlphaComponent(0.22).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor
        ]
        glow.startPoint = CGPoint(x: 0, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 0.5)

        crease.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(0.40).cgColor,
            UIColor.black.withAlphaComponent(0).cgColor
        ]
        crease.startPoint = CGPoint(x: 0, y: 0.5)
        crease.endPoint = CGPoint(x: 1, y: 0.5)

        rootShade.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(0.16).cgColor,
            UIColor.black.withAlphaComponent(0).cgColor
        ]
        rootShade.startPoint = CGPoint(x: 0, y: 0.5)
        rootShade.endPoint = CGPoint(x: 1, y: 0.5)

        claw.fillColor = UIColor.black.withAlphaComponent(0.15).cgColor

        foldShade.colors = [
            UIColor.black.withAlphaComponent(0.30).cgColor,
            UIColor.black.withAlphaComponent(0.08).cgColor,
            UIColor.black.withAlphaComponent(0).cgColor
        ]
        foldShade.startPoint = CGPoint(x: 0, y: 0.5)
        foldShade.endPoint = CGPoint(x: 1, y: 0.5)
        foldShade.isHidden = true

        foldBack.isUserInteractionEnabled = false
        foldBack.isHidden = true
        foldFront.isUserInteractionEnabled = false
        foldFront.isHidden = true

        for layer in [emptyShade, glow, crease, rootShade, claw] {
            view.layer.addSublayer(layer)
            layer.isHidden = true
        }
        view.addSubview(foldBack)
        view.addSubview(foldFront)
    }

    /// 把阴影层提到 backPage 之上、折页之下，保证可见。
    private func raiseShadowLayers(above anchor: CALayer) {
        var current = anchor
        for layer in [emptyShade, glow, crease, rootShade, claw] {
            layer.removeFromSuperlayer()
            view.layer.insertSublayer(layer, above: current)
            current = layer
        }
    }

    private func installPanGesture() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y) * 1.15
    }

    // MARK: - 页面管理

    private func makePage(at index: Int) -> PageContentView {
        let page = PageContentView(text: pages[index], config: config)
        configureReaderPage(
            page,
            reviewEnabled: reviewEnabled,
            onReviewTap: onReviewTap,
            reviewCounts: reviewCounts,
            inlineReviewMarkers: inlineReviewMarkers,
            onInlineReviewTap: onInlineReviewTap,
            onOutsideTap: onOutsideTap
        )
        page.frame = view.bounds
        page.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return page
    }

    private func installPage(at index: Int) {
        currentPageView?.removeFromSuperview()
        let page = makePage(at: index)
        view.insertSubview(page, at: 0)
        currentPageView = page
        currentIndex = index
        angle = .pi
        hideFold()
    }

    func refreshAppearance() {
        currentPageView?.refreshAppearance()
        backPage?.refreshAppearance()
    }

    func updatePages(_ newPages: [String], keepIndex: Int) {
        pages = newPages
        guard !newPages.isEmpty else {
            currentPageView?.removeFromSuperview()
            currentPageView = nil
            currentIndex = 0
            return
        }
        installPage(at: min(max(keepIndex, 0), newPages.count - 1))
    }

    func goToPage(_ index: Int, animated: Bool) {
        guard index >= 0, index < pages.count, index != currentIndex, !interactive, !isAnimating else { return }
        if animated {
            startFold(direction: index > currentIndex ? 1 : -1, target: index)
            animateFold(to: direction > 0 ? 0 : .pi)
        } else {
            installPage(at: index)
            onPageChanged?(index)
        }
    }

    // MARK: - 手势

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard !isAnimating, !interactive else { return }
            let velocity = gesture.velocity(in: view).x
            let tx = gesture.translation(in: view).x
            let dir = (velocity != 0 ? velocity : tx) < 0 ? 1 : -1
            let target = currentIndex + dir
            guard target >= 0, target < pages.count else { return }
            panStartX = gesture.location(in: view).x
            startFold(direction: dir, target: target)
            interactive = true
            updateFromTouch(x: panStartX)

        case .changed:
            guard interactive else { return }
            updateFromTouch(x: gesture.location(in: view).x)

        case .ended, .cancelled, .failed:
            guard interactive else { return }
            interactive = false
            let velocity = gesture.velocity(in: view).x
            // 完成条件：折页越过大半，或手指有明确的继续翻动速度。
            let finish = direction > 0
                ? (angle < .pi * 0.55 || velocity < -520)
                : (angle > .pi * 0.45 || velocity > 520)
            if finish {
                animateFold(to: direction > 0 ? 0 : .pi)
            } else {
                // 回弹到本方向的静止位。
                animateFold(to: direction > 0 ? .pi : 0)
            }

        default:
            break
        }
    }

    /// 手势位移 → 角度。前进：向左拖折起；后退：向右拖让上一页盖回来。
    private func updateFromTouch(x: CGFloat) {
        let w = max(view.bounds.width, 1)
        let t = direction > 0 ? (panStartX - x) / w : (x - panStartX) / w
        if direction > 0 {
            angle = min(max(.pi - t, 0), .pi)
        } else {
            angle = min(max(t, 0), .pi)
        }
        applyFold()
    }

    // MARK: - 折页构建

    private func startFold(direction dir: Int, target: Int) {
        direction = dir
        targetIndex = target
        let w = view.bounds.width, h = view.bounds.height
        guard w > 1, h > 1, let current = currentPageView else { return }

        // 底页：前进显示目标页（下一页），后退同样显示目标页（上一页）。
        backPage?.removeFromSuperview()
        let back = makePage(at: target)
        view.insertSubview(back, aboveSubview: current)
        backPage = back
        raiseShadowLayers(above: back.layer)

        // 正面快照：
        // - 前进：当前页（正在被折走）；
        // - 后退：目标页（上一页折回来盖在前面）。
        var tempPage: UIView?
        let frontSource: UIView
        if dir > 0 {
            frontSource = current
        } else {
            let temp = tempRenderedPage(at: target)
            tempPage = temp
            frontSource = temp
        }
        let frontSnap = snapshot(of: frontSource)
        // 背面快照：与正面同一页内容的镜像 + 淡灰罩。
        let backSnap = snapshot(of: frontSource)
        tempPage?.removeFromSuperview()
        backSnap.transform = CGAffineTransform(scaleX: -1, y: 1)
        let dim = UIView(frame: backSnap.bounds)
        dim.backgroundColor = UIColor(white: 0.45, alpha: 0.16)
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.isUserInteractionEnabled = false
        backSnap.addSubview(dim)

        foldFront.frame = view.bounds
        foldBack.frame = view.bounds
        foldFront.subviews.forEach { $0.removeFromSuperview() }
        foldFront.addSubview(frontSnap)
        foldBack.subviews.forEach { $0.removeFromSuperview() }
        foldBack.addSubview(backSnap)

        if dir > 0 { current.alpha = 0 } // 前进时真页暂时隐身，由快照接管

        view.bringSubviewToFront(foldBack)
        view.bringSubviewToFront(foldFront)

        angle = dir > 0 ? .pi : 0
        applyFold()
    }

    /// 离屏渲染一个目标页并返回（调用方负责 removeFromSuperview）。
    private func tempRenderedPage(at index: Int) -> UIView {
        let page = makePage(at: index)
        page.frame = view.bounds.offsetBy(dx: view.bounds.width * 3, dy: 0)
        view.addSubview(page)
        page.layoutIfNeeded()
        return page
    }

    private func snapshot(of pageView: UIView) -> UIView {
        let w = view.bounds.width, h = view.bounds.height
        let host = UIView(frame: CGRect(x: 0, y: 0, width: w, height: h))
        host.clipsToBounds = true
        host.backgroundColor = UIColor(config.currentTheme.background)
        let iv = UIImageView(image: pageView.snapshotImage())
        iv.frame = host.bounds
        iv.contentMode = .scaleToFill
        iv.isUserInteractionEnabled = false
        host.addSubview(iv)
        return host
    }

    // MARK: - 折页渲染

    private func applyFold() {
        let w = view.bounds.width, h = view.bounds.height
        let a = angle

        // 折页绕左缘 Y 轴旋转，带透视。a=π → 旋转 0（全平），a=0 → 旋转 π（贴背消失）。
        var t = CATransform3DIdentity
        t.m34 = -1 / 1800
        t = CATransform3DRotate(t, .pi - a, 0, 1, 0)
        // a > π/2：正面朝向读者；a < π/2：翻过中线，露出背面。
        let frontVisible = a > .pi / 2

        foldFront.isHidden = !frontVisible
        foldFront.alpha = frontVisible ? 1 : 0
        foldFront.transform3D = t

        foldBack.isHidden = frontVisible
        foldBack.alpha = frontVisible ? 0 : 1
        foldBack.transform3D = t

        foldShade.frame = foldFront.bounds
        foldShade.isHidden = !frontVisible

        updateShadows(progress: 1 - a / .pi, foldFlat: a > .pi / 2)
    }

    /// 阴影/辉光/爪影几何。progress：0 全平 → 1 全折。
    private func updateShadows(progress: CGFloat, foldFlat: Bool) {
        let w = view.bounds.width, h = view.bounds.height
        // 折痕 x：全平(w) → 全折(0)，从右往左扫。
        let foldX = w * (1 - progress)
        let strength = sin(min(progress, 0.96) * .pi / 0.96)

        // 空白区暗化：前进时折页扫过的左侧（因为绕左缘折，扫过的是左边）？
        // 实际折页绕左缘立起再倒向左侧外——参考图中阴影始终在折痕与页面右缘之间。
        // 这里统一做成折痕右侧的渐隐暗带。
        if progress > 0.02, foldX < w - 2 {
            emptyShade.frame = CGRect(x: foldX, y: 0, width: w - foldX, height: h)
            emptyShade.isHidden = false
            emptyShade.opacity = Float(0.7 * strength)
        } else {
            emptyShade.isHidden = true
        }

        // 底页辉光：紧贴折痕右侧的光带。
        if progress > 0.05, foldX < w - 6 {
            glow.frame = CGRect(x: foldX, y: 0, width: min(110, w - foldX), height: h)
            glow.isHidden = false
            glow.opacity = Float(0.55 * strength)
        } else {
            glow.isHidden = true
        }

        // 折痕锐利窄阴影。
        if progress > 0.02, foldX > 6 {
            crease.frame = CGRect(x: foldX - 15, y: 0, width: 30, height: h)
            crease.isHidden = false
            crease.opacity = Float(0.95 * strength)
        } else {
            crease.isHidden = true
        }

        // 根部柔和暗带：折痕左侧稍宽的一条。
        if progress > 0.02, foldX > 44 {
            rootShade.frame = CGRect(x: foldX - 88, y: 0, width: 176, height: h)
            rootShade.isHidden = false
            rootShade.opacity = Float(0.7 * strength)
        } else {
            rootShade.isHidden = true
        }

        // 爪影：从折痕向右拖出的弧形暗楔。
        if progress > 0.08, progress < 0.95, foldX < w - 40 {
            let path = UIBezierPath()
            path.move(to: CGPoint(x: foldX, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: foldX, y: h),
                controlPoint: CGPoint(x: foldX + (w - foldX) * 0.24, y: h * 0.5)
            )
            path.addLine(to: CGPoint(x: foldX + 30, y: h))
            path.addQuadCurve(
                to: CGPoint(x: foldX + 30, y: 0),
                controlPoint: CGPoint(x: foldX + 30 + (w - foldX) * 0.18, y: h * 0.5)
            )
            path.close()
            claw.path = path.cgPath
            claw.isHidden = false
            claw.opacity = Float(0.6 * strength)
        } else {
            claw.isHidden = true
        }

        foldShade.opacity = foldFlat ? Float(0.4 + 0.6 * progress) : 0.2
    }

    private func hideFold() {
        foldFront.isHidden = true
        foldBack.isHidden = true
        [emptyShade, glow, crease, rootShade, claw].forEach { $0.isHidden = true }
    }

    /// 折页结束（完成或回弹）后的清理。
    private func teardownFold() {
        hideFold()
        foldFront.subviews.forEach { $0.removeFromSuperview() }
        foldBack.subviews.forEach { $0.removeFromSuperview() }
        backPage?.removeFromSuperview()
        backPage = nil
        currentPageView?.alpha = 1
        angle = .pi
        isAnimating = false
    }

    /// 角度动画：target 到达"终点"（前进 0 / 后退 π）就落页，否则是回弹。
    private func animateFold(to target: CGFloat) {
        isAnimating = true
        let reachesEnd = direction > 0 ? target == 0 : target == .pi
        let duration = 0.26 + abs(target - angle) / .pi * 0.20
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) { [weak self] in
            guard let self else { return }
            self.angle = target
            self.applyFold()
        } completion: { [weak self] _ in
            guard let self else { return }
            if reachesEnd {
                let landed = self.targetIndex
                self.teardownFold()
                self.installPage(at: landed)
                self.onPageChanged?(landed)
            } else {
                self.teardownFold()
            }
        }
    }
}

// MARK: - UIView 快照扩展

extension UIView {
    /// 离屏快照。要求视图已在窗口层级中（或用 afterScreenUpdates 渲染）。
    func snapshotImage() -> UIImage? {
        // 若不在窗口里（离屏 temp 页），先临时塞进 keyWindow 快照再移除由调用方处理；
        // drawHierarchy 对未上屏视图退化为 layer 渲染，这里统一用 renderer 兜底。
        if window != nil {
            return UIGraphicsImageRenderer(bounds: bounds).image { _ in
                drawHierarchy(in: bounds, afterScreenUpdates: true)
            }
        }
        return UIGraphicsImageRenderer(bounds: bounds).image { _ in
            layer.render(in: UIGraphicsGetCurrentContext()!)
        }
    }
}
