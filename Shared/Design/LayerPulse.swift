import QuartzCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A circle that pulses forever, run by Core Animation.
///
/// SwiftUI drives its own animations (a `TimelineView`, `repeatForever`) from inside the
/// app: every frame re-renders the view graph and lays out the window. A pulse that runs
/// for a whole workday kept the Mac app at about 13% CPU. A Core Animation animation is
/// handed to the render server once and costs the app nothing per frame, and it stops
/// on its own while the window is hidden.
struct LayerPulse: View {
    enum Style: Equatable {
        case ring(lineWidth: CGFloat)
        case fill
    }

    var color: Color
    var style: Style
    var fromScale: CGFloat
    var toScale: CGFloat
    var fromOpacity: Float = 1
    var toOpacity: Float = 1
    var duration: TimeInterval
    /// Back and forth (a breath) rather than restarting from the beginning (a ripple).
    var autoreverses = false
    var timing = CAMediaTimingFunction(name: .easeInEaseOut)

    var body: some View {
        PulseRepresentable(spec: self)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    fileprivate func animation() -> CAAnimation {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = fromScale
        scale.toValue = toScale
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fromOpacity
        fade.toValue = toOpacity
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = duration
        group.autoreverses = autoreverses
        group.repeatCount = .infinity
        group.timingFunction = timing
        group.isRemovedOnCompletion = false
        return group
    }

    /// What the animation is made of: SwiftUI calls update on every parent render, and
    /// restarting the pulse then would make it jump.
    fileprivate var signature: String {
        "\(color)|\(style)|\(fromScale)|\(toScale)|\(fromOpacity)|\(toOpacity)|\(duration)|\(autoreverses)"
    }

    fileprivate var cgColor: CGColor {
        #if os(macOS)
        NSColor(color).cgColor
        #else
        UIColor(color).cgColor
        #endif
    }
}

#if os(macOS)
private struct PulseRepresentable: NSViewRepresentable {
    var spec: LayerPulse
    func makeNSView(context: Context) -> PulseView { PulseView() }
    func updateNSView(_ view: PulseView, context: Context) { view.spec = spec }
}

private final class PulseView: NSView {
    private let shape = CAShapeLayer()
    var spec: LayerPulse? {
        didSet { if oldValue?.signature != spec?.signature { restyle() } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(shape)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        reshape()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restart()
    }

    private func restyle() {
        PulseLayer.style(shape, spec: spec)
        restart()
    }

    private func reshape() {
        PulseLayer.reshape(shape, in: bounds)
    }

    private func restart() {
        PulseLayer.restart(shape, spec: spec, running: window != nil)
    }
}
#else
private struct PulseRepresentable: UIViewRepresentable {
    var spec: LayerPulse
    func makeUIView(context: Context) -> PulseView { PulseView() }
    func updateUIView(_ view: PulseView, context: Context) { view.spec = spec }
}

private final class PulseView: UIView {
    private let shape = CAShapeLayer()
    var spec: LayerPulse? {
        didSet { if oldValue?.signature != spec?.signature { restyle() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.addSublayer(shape)
        // iOS drops every layer animation when the app goes to the background.
        NotificationCenter.default.addObserver(self, selector: #selector(restart),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        PulseLayer.reshape(shape, in: bounds)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        restart()
    }

    private func restyle() {
        PulseLayer.style(shape, spec: spec)
        restart()
    }

    @objc private func restart() {
        PulseLayer.restart(shape, spec: spec, running: window != nil)
    }
}
#endif

/// The layer work both platforms share.
private enum PulseLayer {
    static let key = "tf.pulse"

    static func style(_ shape: CAShapeLayer, spec: LayerPulse?) {
        guard let spec else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch spec.style {
        case .ring(let lineWidth):
            shape.fillColor = nil
            shape.strokeColor = spec.cgColor
            shape.lineWidth = lineWidth
        case .fill:
            shape.fillColor = spec.cgColor
            shape.strokeColor = nil
        }
        CATransaction.commit()
    }

    static func reshape(_ shape: CAShapeLayer, in bounds: CGRect) {
        guard shape.bounds.size != bounds.size || shape.position != CGPoint(x: bounds.midX, y: bounds.midY) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.bounds = CGRect(origin: .zero, size: bounds.size)
        shape.position = CGPoint(x: bounds.midX, y: bounds.midY)
        let inset = (shape.strokeColor == nil ? 0 : shape.lineWidth / 2)
        shape.path = CGPath(ellipseIn: shape.bounds.insetBy(dx: inset, dy: inset), transform: nil)
        CATransaction.commit()
    }

    /// Adds the animation once; a new spec replaces it, a hidden view drops it.
    static func restart(_ shape: CAShapeLayer, spec: LayerPulse?, running: Bool) {
        guard running, let spec else {
            shape.removeAnimation(forKey: key)
            return
        }
        shape.removeAnimation(forKey: key)
        shape.add(spec.animation(), forKey: key)
    }
}
