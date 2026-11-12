import Cocoa
import WebKit

@main
final class PointerSmoke: NSObject, WKNavigationDelegate {
    static var instance: PointerSmoke!
    let delegate = MouseCaptureDelegate()
    var window: NSWindow!
    var web: WKWebView!
    var approved = false
    var captureCount = 0
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        instance = PointerSmoke()
        instance.run()
        app.run()
    }
    func fail(_ text: String) { fputs(text + "\n", stderr); exit(1) }
    func run() {
        window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 800, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = true
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        window.contentView = web
        web.navigationDelegate = self
        web.uiDelegate = delegate
        delegate.approveMouseCapture = { view in
            self.approved = MouseCaptureDelegate.isInteractiveSecurePage(view)
            if self.approved { self.captureCount += 1 }
            return self.approved
        }
        let backgroundView = WKWebView(frame: .zero)
        guard !MouseCaptureDelegate.isInteractiveSecurePage(backgroundView) else {
            fail("Background content was allowed to capture the mouse"); return
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        web.loadHTMLString("<html><body><canvas id='game' width='700' height='500'></canvas></body></html>", baseURL: URL(string: "https://pointer-test.invalid"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { self.fail("Pointer lock timed out") }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.getElementById('game').requestPointerLock(); null") { _, error in
            if let error = error { self.fail("Pointer request failed: " + error.localizedDescription) }
            self.checkLock(attempt: 0)
        }
    }
    func checkLock(attempt: Int) {
        web.evaluateJavaScript("document.pointerLockElement === document.getElementById('game')") { value, _ in
            if value as? Bool == true, self.approved {
                print("PASS: Native WebKit pointer lock authorized and acquired")
                self.web.evaluateJavaScript("document.exitPointerLock(); null") { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.web.evaluateJavaScript("document.pointerLockElement === null") { unlocked, _ in
                            guard unlocked as? Bool == true else { self.fail("Pointer did not release"); return }
                            print("PASS: Native WebKit pointer lock released")
                            if self.captureCount == 1 {
                                self.web.evaluateJavaScript("document.getElementById('game').requestPointerLock(); null") { _, error in
                                    if let error = error { self.fail(error.localizedDescription); return }
                                    self.checkLock(attempt: 0)
                                }
                            } else {
                                print("PASS: Foreground HTTPS page reacquired pointer lock without a modal prompt")
                                exit(0)
                            }
                        }
                    }
                }
            } else if attempt < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.checkLock(attempt: attempt + 1) }
            } else { self.fail("WebKit did not acquire pointer lock") }
        }
    }
}
