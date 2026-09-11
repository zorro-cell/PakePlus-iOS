import SwiftUI
import UIKit
import WebKit

private let chatGPTiPadSafariUserAgent = "Mozilla/5.0 (iPad; CPU OS 16_5_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1"

struct WebView: UIViewRepresentable {
    let webUrl: URL
    let debug: Bool
    let onLoadFinished: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoadFinished: onLoadFinished)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let viewportScript = WKUserScript(
            source: """
                var meta = document.querySelector('meta[name=viewport]');
                if (!meta) {
                    meta = document.createElement('meta');
                    meta.name = 'viewport';
                    document.head.appendChild(meta);
                }
                meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(viewportScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = false

        // Match iPad Safari on the target iPadOS release. The Info.plist value
        // is generated from ppconfig; keep this fallback for direct Xcode runs.
        let configuredUserAgent = Bundle.main.object(forInfoDictionaryKey: "USERAGENT") as? String
        webView.customUserAgent = configuredUserAgent?.isEmpty == false
            ? configuredUserAgent
            : chatGPTiPadSafariUserAgent

        if #available(iOS 16.4, *) {
            webView.isInspectable = debug
        }
        webView.load(URLRequest(url: webUrl))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let onLoadFinished: (() -> Void)?
    private var didFinishOnce = false

    init(onLoadFinished: (() -> Void)?) {
        self.onLoadFinished = onLoadFinished
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !didFinishOnce else { return }
        didFinishOnce = true
        onLoadFinished?()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil,
           let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow)
            return
        }

        if !["http", "https", "about", "blob", "data"].contains(scheme) {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
