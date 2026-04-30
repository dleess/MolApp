import SwiftUI
import WebKit

struct MolStarWebView: UIViewRepresentable {
    let htmlResourceName: String

    init(htmlResourceName: String = "viewer") {
        self.htmlResourceName = htmlResourceName
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
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
}
