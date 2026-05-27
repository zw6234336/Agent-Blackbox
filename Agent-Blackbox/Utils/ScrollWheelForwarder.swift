import SwiftUI
import AppKit

// MARK: - ScrollWheelForwarder

/// A transparent `NSViewRepresentable` overlay that keeps scroll-wheel event
/// delivery alive on macOS SwiftUI.
///
/// **Background**: SwiftUI on macOS has a long-standing bug where, after the
/// app has been idle for a while or after interacting with menus / sheets /
/// popovers, `scrollWheel` events silently stop reaching `ScrollView`s.
/// The scrollbar thumb still works because it doesn't go through SwiftUI's
/// internal wheel dispatcher.
///
/// **How this works**: By placing a thin `NSView` overlay (via
/// `NSViewRepresentable`) that:
///   1. Maintains an always-active `NSTrackingArea`, preventing AppKit from
///      optimising away mouse-tracking for the region.
///   2. Overrides `scrollWheel(with:)` to walk the **entire** superview chain
///      until it finds the nearest `NSScrollView`, then forwards the event
///      directly to it.  If no `NSScrollView` is found, it falls back to
///      forwarding to `nextResponder` so the event still has a chance to
///      reach the correct handler via the responder chain.
///   3. Returns `nil` from `hitTest(_:)` so it never intercepts clicks,
///      drags, or any other interaction — it is purely a scroll-event
///      "keep-alive" shim.
///   4. Overrides `mouseEntered` / `mouseMoved` to keep the AppKit event
///      routing table entry for this view warm even after long idle periods.
///
/// Usage:
/// ```swift
/// ScrollView {
///     // ...
/// }
/// .scrollWheelKeepAlive()   // ← attach to any ScrollView
/// ```
struct ScrollWheelForwarder: NSViewRepresentable {

    func makeNSView(context: Context) -> ForwarderView {
        let view = ForwarderView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        return view
    }

    func updateNSView(_ nsView: ForwarderView, context: Context) {}

    // MARK: - ForwarderView

    final class ForwarderView: NSView {

        // Keep a full-coverage tracking area registered at all times so
        // AppKit never drops this view from its event routing tables.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas {
                removeTrackingArea(area)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [
                    .mouseEnteredAndExited,
                    .mouseMoved,
                    .activeAlways,
                    .inVisibleRect
                ],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
        }

        // Walk the superview chain to find the nearest NSScrollView and
        // forward the scroll-wheel event directly to it.  This is the key
        // fix: SwiftUI's deeply nested NSView hierarchy means the immediate
        // `superview` is almost certainly a layout container (e.g.
        // _NSHostingView, NSSplitView, etc.), NOT the actual NSScrollView.
        // Forwarding only to `superview` (the old approach) lost the event
        // in the void.  Walking up until we hit NSScrollView guarantees
        // delivery even after SwiftUI's internal dispatcher has gone dormant.
        override func scrollWheel(with event: NSEvent) {
            // Walk up the superview chain to find an NSScrollView.
            var candidate = superview
            while let view = candidate {
                if let scrollView = view as? NSScrollView {
                    scrollView.scrollWheel(with: event)
                    return
                }
                candidate = view.superview
            }

            // Fallback: no NSScrollView found — use the responder chain
            // so the event still has a chance to be handled somewhere.
            nextResponder?.scrollWheel(with: event)
        }

        // Keep-alive: absorbing mouseEntered / mouseMoved keeps this view's
        // tracking area entry warm in AppKit's dispatch tables.
        override func mouseEntered(with event: NSEvent) {
            // no-op: intentionally empty to keep the tracking area alive
        }

        override func mouseMoved(with event: NSEvent) {
            // no-op: intentionally empty to keep the tracking area alive
        }

        // Return nil so this overlay never captures hit-tests — clicks,
        // drags, context menus, etc. all pass straight through.
        override func hitTest(_ point: NSPoint) -> NSView? {
            return nil
        }

        // Likewise, don't accept first-responder status.
        override var acceptsFirstResponder: Bool { false }
    }
}

// MARK: - View Extension

extension View {
    /// Attaches a transparent AppKit-level scroll-wheel event forwarder to
    /// this view.  Use on any `ScrollView` that might lose scroll capability
    /// after the app has been idle or after menu / sheet interactions.
    func scrollWheelKeepAlive() -> some View {
        self.overlay(ScrollWheelForwarder())
    }
}

// MARK: - NativeScrollView

/// A vertically scrolling SwiftUI container backed by a native Cocoa `NSScrollView`
/// to completely bypass SwiftUI's buggy, dormant-prone gesture router on macOS.
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
        
        let clipView = FlippedClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setContentCompressionResistancePriority(.required, for: .vertical)
        hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
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
        if let hostingView = nsView.documentView as? NSHostingView<Content> {
            hostingView.rootView = content
            hostingView.invalidateIntrinsicContentSize()
        }
    }
}

/// A flipped custom clip view so vertical scrolling starts from the top on macOS.
final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

