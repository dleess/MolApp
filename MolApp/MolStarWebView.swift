import SwiftUI
import WebKit

struct MolStarWebView: UIViewRepresentable {
    let htmlResourceName: String
    @ObservedObject var bridge: MolStarBridge

    init(htmlResourceName: String = "viewer", bridge: MolStarBridge) {
        self.htmlResourceName = htmlResourceName
        self.bridge = bridge
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(bridge: bridge, htmlResourceName: htmlResourceName)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(context.coordinator, name: "molapp")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false

        let hoverRecognizer = UIHoverGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleHover(_:))
        )
        hoverRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        webView.addGestureRecognizer(hoverRecognizer)

        let pinchRecognizer = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinchRecognizer.delegate = context.coordinator
        webView.addGestureRecognizer(pinchRecognizer)
        webView.navigationDelegate = context.coordinator
        context.coordinator.attach(webView: webView)

        context.coordinator.loadViewerHTML(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "molapp")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, UIGestureRecognizerDelegate {
        private let bridge: MolStarBridge
        private let htmlResourceName: String
        private weak var webView: WKWebView?

        init(bridge: MolStarBridge, htmlResourceName: String) {
            self.bridge = bridge
            self.htmlResourceName = htmlResourceName
        }

        func attach(webView: WKWebView) {
            self.webView = webView
        }

        func loadViewerHTML(in webView: WKWebView) {
            // Reset readiness here rather than at the call sites: this is the one path every load
            // and reload routes through, so the flag can never outlive the page it describes.
            bridge.attach(webView: webView)

            guard let htmlURL = Bundle.main.url(forResource: htmlResourceName, withExtension: "html") else {
                webView.loadHTMLString(
                    """
                    <!doctype html>
                    <html><body style="background:#111;color:white;font:17px -apple-system;padding:20px">
                    Viewer resource not found.
                    </body></html>
                    """,
                    baseURL: nil
                )
                return
            }

            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // The viewer's JS is gone, so it cannot report its own death. Reload from the resource
            // rather than reload(): after a crash the last URL may be gone, and every command sent
            // meanwhile would be dropped against a dead page.
            loadViewerHTML(in: webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            bridge.userContentController(userContentController, didReceive: message)
        }

        @objc func handleHover(_ gesture: UIHoverGestureRecognizer) {
            guard let webView else { return }
            switch gesture.state {
            case .began, .changed:
                let pt = gesture.location(in: webView)
                bridge.updateHoverPoint(pt)
                let js = "window.molapp?.handlePencilHover?.(\(pt.x), \(pt.y));"
                webView.evaluateJavaScript(js, completionHandler: nil)
            case .ended, .cancelled:
                bridge.updateHoverPoint(nil)
                webView.evaluateJavaScript("window.molapp?.handlePencilHoverEnd?.();", completionHandler: nil)
            default:
                break
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let webView else { return }

            switch gesture.state {
            case .began, .changed:
                let scale = gesture.scale
                let pt = gesture.location(in: webView)
                let js = "window.molapp?.handleNativePinch?.(\(scale), \(pt.x), \(pt.y));"
                webView.evaluateJavaScript(js, completionHandler: nil)
                gesture.scale = 1
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
