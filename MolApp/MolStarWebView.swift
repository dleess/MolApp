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
        Coordinator(bridge: bridge)
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
        webView.addGestureRecognizer(hoverRecognizer)

        let pinchRecognizer = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        pinchRecognizer.delegate = context.coordinator
        webView.addGestureRecognizer(pinchRecognizer)
        context.coordinator.attach(webView: webView)

        bridge.attach(webView: webView)
        loadViewerHTML(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url == nil {
            loadViewerHTML(in: webView)
        }
    }

    private func loadViewerHTML(in webView: WKWebView) {
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

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "molapp")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, UIGestureRecognizerDelegate {
        private let bridge: MolStarBridge
        private weak var webView: WKWebView?

        init(bridge: MolStarBridge) {
            self.bridge = bridge
        }

        func attach(webView: WKWebView) {
            self.webView = webView
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
