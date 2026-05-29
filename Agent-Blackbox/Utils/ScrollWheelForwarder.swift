import SwiftUI
import AppKit

// MARK: - NativeScrollView

/// A vertically scrolling SwiftUI container backed by a native Cocoa `NSScrollView`.
///
/// **Why this exists**: SwiftUI's `ScrollView` on macOS has a long-standing bug
/// where scroll-wheel events silently stop reaching the view after the app has
/// been idle, after interacting with menus/sheets/popovers, or after window
/// focus changes.
///
/// By wrapping content in a genuine `NSScrollView` + `NSHostingView`, scroll
/// events are handled by AppKit's event chain rather than SwiftUI's internal
/// (and sometimes dormant) gesture router.
///
/// The inner `ResponsiveScrollView` subclass also re-engages AppKit's
/// "responsive scrolling" machinery after idle / sleep periods by calling
/// `reflectScrolledClipView` when the window or application re-activates.
///
/// Usage:
/// ```swift
/// NativeScrollView {
///     VStack { ... }
/// }
/// ```
struct NativeScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ResponsiveScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        if #available(macOS 10.16, *) {
            scrollView.verticalScrollElasticity = .none
        }

        let clipView = FlippedClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        // Use a custom hosting view that clamps intrinsicContentSize
        // so AppKit never sees {inf, xxx} from SwiftUI content that uses
        // maxWidth: .infinity / FlexFrameLayout.
        let hostingView = BoundedHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = hostingView

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: clipView.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
            hostingView.widthAnchor.constraint(equalTo: clipView.widthAnchor),
            hostingView.bottomAnchor.constraint(greaterThanOrEqualTo: clipView.bottomAnchor)
        ])

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let hostingView = nsView.documentView as? BoundedHostingView<Content> {
            hostingView.rootView = content
        }
    }
}

// MARK: - ResponsiveScrollView

/// A custom `NSScrollView` that re-establishes scroll responsiveness after the
/// app or window has been idle / backgrounded for extended periods.
///
/// ## The Problem
///
/// After the app sits idle for a long time (display sleep, App Nap, or just
/// no interaction for hours), scroll-wheel / trackpad events stop scrolling
/// the content — on **all** pages, not just specific ones.  The scroll bar
/// thumb often still works because that path hits the scroller knob directly
/// rather than going through the normal event pipeline.
///
/// ## Root Causes (multiple, interacting)
///
/// 1. **SwiftUI's internal event-routing layer**: SwiftUI uses a private
///    `NSWindow` subclass whose `sendEvent` routes scroll-wheel events to
///    SwiftUI's internal gesture system before they reach AppKit's standard
///    hit-test → `scrollWheel(with:)` path.  After idle this routing layer
///    can become "dormant" and stop forwarding events to child NSViews.
///
/// 2. **macOS responsive scrolling** (Mavericks+): NSScrollView decouples
///    scroll event handling into a secondary event loop for smooth over-draw
///    (WWDC 2013 Session 215).  This loop can be throttled / suspended by
///    macOS during idle and may not wake up cleanly when the user returns.
///
/// 3. **Momentum-phase scroll events** (trackpad inertia scrolling): These
///    may be routed through the responder chain / first-responder rather than
///    hit-testing, meaning they can be swallowed by a stale SwiftUI internal
///    view that is the current first-responder.
///
/// ## What This Subclass Does
///
/// - Accepts first-responder status so momentum-phase scroll events and any
///   responder-chain-routed scroll events reach this NSScrollView (cause 3).
/// - On window-become-key / app-become-active, calls
///   `reflectScrolledClipView` to re-sync the responsive-scrolling pipeline's
///   internal state (cause 2), and forces a layout pass.
/// - Combined with `AppDelegate.applicationDidBecomeActive` which calls
///   `window.makeKey()`, the SwiftUI event-routing layer is forced to
///   re-initialise (cause 1).
final class ResponsiveScrollView: NSScrollView {

    // MARK: First-responder support

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        // Accept the first mouse-down after window activation so that the
        // accompanying scroll-wheel events are also delivered.
        return true
    }

    // MARK: Activation observers

    private var windowKeyObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        teardownObservers()

        guard let window = self.window else { return }

        // When this window becomes key (user clicked on it, or macOS brought
        // it to the front after idle), nudge the scroll machinery awake.
        windowKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.wakeUpScrollPipeline()
        }

        // Also handle the case where the *application* becomes active but the
        // window was already key (e.g. returning from another space).
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.wakeUpScrollPipeline()
        }

        // IMPORTANT: When SwiftUI switches tabs (e.g. from "日志" to "看板")
        // the old view is destroyed and a new one is created.  At this point
        // the window is already key and the app is already active, so neither
        // didBecomeKey nor didBecomeActive will fire.  We must do an immediate
        // wake-up so the new NSScrollView's responsive-scrolling pipeline is
        // engaged from the first moment it appears on screen.
        //
        // Use async to defer until after the current layout pass completes,
        // ensuring the view hierarchy is fully attached.
        DispatchQueue.main.async { [weak self] in
            self?.wakeUpScrollPipeline()
        }
    }

    // MARK: Wake-up

    /// Force the scroll pipeline back to life after idle / sleep.
    ///
    /// This does several things that together cover the known failure modes:
    /// 1. Claims first-responder so momentum-phase scroll events reach us
    ///    (these may be routed through the responder chain rather than
    ///    hit-testing).
    /// 2. Calls `reflectScrolledClipView` to re-sync the responsive-scrolling
    ///    machinery's internal state — this is the key fix for cause 2.
    /// 3. Triggers a layout pass so any stale geometry is recalculated.
    private func wakeUpScrollPipeline() {
        guard let window = self.window, window.isKeyWindow else { return }

        // Step 1: Become first-responder so that momentum-phase and
        // responder-chain-routed scroll events arrive at this NSScrollView.
        // Only do this if no other ResponsiveScrollView has already claimed it
        // (avoids thrashing when multiple NativeScrollViews exist on screen).
        if let fr = window.firstResponder,
           fr !== self,
           !(fr is ResponsiveScrollView) {
            window.makeFirstResponder(self)
        }

        // Step 2: Re-engage responsive scrolling.  Calling
        // reflectScrolledClipView with the current clip-view forces AppKit to
        // recalculate scroller state and re-register the responsive-scrolling
        // event pipeline.  Without this, the secondary event loop that handles
        // smooth scrolling stays suspended after idle.
        reflectScrolledClipView(contentView)

        // Step 3: Force a layout pass to clear any stale geometry that might
        // prevent the scroll view from recognising it needs to scroll.
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    // MARK: Cleanup

    private func teardownObservers() {
        if let obs = windowKeyObserver {
            NotificationCenter.default.removeObserver(obs)
            windowKeyObserver = nil
        }
        if let obs = appActiveObserver {
            NotificationCenter.default.removeObserver(obs)
            appActiveObserver = nil
        }
    }

    deinit {
        teardownObservers()
    }
}

// MARK: - BoundedHostingView

/// A custom `NSHostingView` that prevents `intrinsicContentSize` from returning
/// infinite values. When SwiftUI content uses `maxWidth: .infinity` or
/// `FlexFrameLayout`, the standard `NSHostingView` reports `{inf, height}` which
/// causes `NSInvalidArgumentException` crashes in AppKit's constraint system:
/// `"Invalid size {inf, xxx} returned by intrinsicContentSize"`.
///
/// This subclass clamps the width to the current frame width (or a sane fallback)
/// so Auto Layout never sees infinity.
private final class BoundedHostingView<Content: View>: NSHostingView<Content> {

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        // Clamp infinite width to the current frame width.
        // If the frame is also zero (first layout pass), use a large fallback.
        let clampedWidth: CGFloat
        if size.width == .infinity || size.width.isNaN {
            clampedWidth = frame.width > 0 ? frame.width : 10000
        } else {
            clampedWidth = size.width
        }
        let clampedHeight: CGFloat
        if size.height == .infinity || size.height.isNaN {
            clampedHeight = frame.height > 0 ? frame.height : 10000
        } else {
            clampedHeight = size.height
        }
        return NSSize(width: clampedWidth, height: clampedHeight)
    }
}

// MARK: - FlippedClipView

/// A flipped custom clip view so vertical scrolling starts from the top on macOS.
final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}
