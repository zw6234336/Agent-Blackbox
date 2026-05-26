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
///   2. Overrides `scrollWheel(with:)` to forward the event up the
///      responder / superview chain at the **AppKit** level, bypassing
///      SwiftUI's sometimes-dormant internal routing.
///   3. Returns `nil` from `hitTest(_:)` so it never intercepts clicks,
///      drags, or any other interaction — it is purely a scroll-event
///      "keep-alive" shim.
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

        // Forward scroll-wheel events up the AppKit superview chain.
        // This is the key fix: even if SwiftUI's internal dispatcher has
        // gone dormant, the AppKit superview (which hosts the SwiftUI
        // ScrollView's backing NSScrollView) will still process the event.
        override func scrollWheel(with event: NSEvent) {
            superview?.scrollWheel(with: event)
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
