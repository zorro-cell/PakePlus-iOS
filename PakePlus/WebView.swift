import SwiftUI
import UIKit
import WebKit

private let grokSafariUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1"

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
                meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
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

        // xAI's current native app and account service require a newer iOS
        // browser environment. Present a supported Mobile Safari identity while
        // retaining the immersive web container needed on the iOS 16.6 device.
        webView.customUserAgent = grokSafariUserAgent

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
    private weak var authenticationWebView: WKWebView?

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
        guard navigationAction.targetFrame == nil else { return nil }

        // OAuth relies on a real auxiliary browsing context and window.opener.
        // Returning a WebKit-created child preserves that relationship, the
        // shared data store, redirect state, and the window.close callback.
        authenticationWebView?.removeFromSuperview()

        let popup = WKWebView(frame: webView.bounds, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        popup.customUserAgent = grokSafariUserAgent
        popup.allowsBackForwardNavigationGestures = true
        popup.isOpaque = true
        popup.backgroundColor = .black
        popup.scrollView.backgroundColor = .black
        popup.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        webView.addSubview(popup)
        authenticationWebView = popup
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let authenticationWebView,
              webView === authenticationWebView else { return }
        webView.removeFromSuperview()
        self.authenticationWebView = nil
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
