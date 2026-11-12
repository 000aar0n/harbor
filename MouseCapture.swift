import Cocoa
import WebKit

// WebKit exposes pointer-lock authorization through these Objective-C delegate
// selectors, but not the public WKUIDelegate Swift interface. Keep the bridge
// isolated: it may need updating for future macOS WebKit releases.
class MouseCaptureDelegate: NSObject, WKUIDelegate {
    var approveMouseCapture: ((WKWebView) -> Bool)?
    var mouseCaptureChanged: ((Bool) -> Void)?

    // Authorize synchronously. Presenting a modal alert here moves keyboard
    // focus away from the page in the middle of a game's Play/fullscreen flow.
    // WebKit enforces its own user-activation and frame-origin restrictions.
    static func isInteractiveSecurePage(_ webView: WKWebView) -> Bool {
        NSApp.isActive && webView.window?.isKeyWindow == true && webView.url?.scheme == "https"
    }

    @objc(_webViewDidRequestPointerLock:completionHandler:)
    func requestPointerLock(_ webView: WKWebView, completionHandler: @escaping (Bool) -> Void) {
        let allowed = approveMouseCapture?(webView) ?? false
        completionHandler(allowed)
        if allowed { mouseCaptureChanged?(true) }
    }

    @objc(_webViewDidLosePointerLock:)
    func lostPointerLock(_ webView: WKWebView) {
        mouseCaptureChanged?(false)
    }
}
