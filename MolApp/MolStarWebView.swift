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
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
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

    final class Coordinator: NSObject, WKScriptMessageHandler {
        private let bridge: MolStarBridge

        init(bridge: MolStarBridge) {
            self.bridge = bridge
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            bridge.userContentController(userContentController, didReceive: message)
        }
    }
}
