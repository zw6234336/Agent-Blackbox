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
/// By wrapping content in a genuine `NSScrollView` + `NSHostingView`, all
/// scroll-wheel events are handled by AppKit's battle-tested event chain —
/// no synthetic events, no event monitors, no keep-alive timers needed.
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
        let scrollView = NSScrollView()
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
