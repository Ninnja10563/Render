import AppKit
import SwiftUI

/// Reads the enclosing native clip view, including programmatic scrolling and viewport resizing.
struct NativeScrollViewport: NSViewRepresentable {
    let changed: (CGPoint,CGSize) -> Void
    func makeNSView(context: Context) -> ScrollViewportObserver { ScrollViewportObserver(changed: changed) }
    func updateNSView(_ view: ScrollViewportObserver,context: Context) { view.changed = changed; view.connect() }
}

final class ScrollViewportObserver: NSView {
    var changed: (CGPoint,CGSize) -> Void
    private weak var observedClip: NSClipView?
    private var observers: [NSObjectProtocol] = []
    init(changed: @escaping (CGPoint,CGSize) -> Void) { self.changed = changed; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { disconnect() }
        else { DispatchQueue.main.async { [weak self] in self?.connect() } }
    }
    func connect() {
        guard window != nil, let clip = enclosingScrollView?.contentView else { return }
        if observedClip !== clip {
            disconnect(); observedClip = clip
            clip.postsBoundsChangedNotifications = true; clip.postsFrameChangedNotifications = true
            for name in [NSView.boundsDidChangeNotification,NSView.frameDidChangeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name,object: clip,queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                })
            }
        }
        report()
    }
    private func report() {
        guard let clip = observedClip, let document = clip.documentView else { return }
        let origin = CGPoint(x: clip.bounds.minX,y: document.isFlipped ? clip.bounds.minY : max(0,document.bounds.height - clip.bounds.maxY))
        // State mutations must occur outside SwiftUI's representable update pass.
        let size = clip.bounds.size
        DispatchQueue.main.async { [weak self] in guard self?.window != nil else { return }; self?.changed(origin,size) }
    }
    private func disconnect() { observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll(); observedClip = nil }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
