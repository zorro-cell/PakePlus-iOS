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

        let compatibilityScript = WKUserScript(
            source: """
                (() => {
                    const marker = 'Silero VAD failed to load';

                    const dismissKnownToast = () => {
                        const selectors = [
                            '[role="alert"]',
                            '[data-sonner-toast]',
                            '[data-testid*="toast"]'
                        ];
                        for (const element of document.querySelectorAll(selectors.join(','))) {
                            if (!element.textContent?.includes(marker)) continue;
                            const button = element.querySelector('button');
                            if (button) button.click();
                            else element.remove();
                            return true;
                        }
                        return false;
                    };

                    const dismissFallback = () => {
                        const walker = document.createTreeWalker(
                            document.body,
                            NodeFilter.SHOW_TEXT
                        );
                        while (walker.nextNode()) {
                            const node = walker.currentNode;
                            if (!node.nodeValue?.includes(marker)) continue;
                            let container = node.parentElement;
                            for (let depth = 0; container && depth < 6; depth++) {
                                const button = container.querySelector('button');
                                if (button && container.textContent.length < 600) {
                                    button.click();
                                    return;
                                }
                                container = container.parentElement;
                            }
                        }
                    };

                    const dismissSileroWarning = () => {
                        if (!dismissKnownToast()) dismissFallback();
                    };

                    const normalizeText = (value) =>
                        (value || '').replace(/\\s+/g, ' ').trim();

                    const disclaimerTexts = new Set([
                        'ChatGPT 也可能会犯错。请核查重要信息。',
                        'ChatGPT 也会犯错，请核查重要信息。',
                        'ChatGPT can make mistakes. Check important info.',
                        'ChatGPT can make mistakes. Consider checking important information.'
                    ]);

                    const hideDisclaimer = () => {
                        const walker = document.createTreeWalker(
                            document.body,
                            NodeFilter.SHOW_TEXT
                        );
                        while (walker.nextNode()) {
                            const node = walker.currentNode;
                            const text = normalizeText(node.nodeValue);
                            if (!disclaimerTexts.has(text)) continue;

                            let container = node.parentElement;
                            let outermostExactContainer = container;
                            while (container?.parentElement) {
                                const parent = container.parentElement;
                                if (parent === document.body) break;
                                if (normalizeText(parent.textContent) !== text) break;
                                outermostExactContainer = parent;
                                container = parent;
                            }
                            outermostExactContainer?.style.setProperty(
                                'display',
                                'none',
                                'important'
                            );
                        }
                    };

                    const applyCompatibilityFixes = () => {
                        dismissSileroWarning();
                        hideDisclaimer();
                    };

                    new MutationObserver(applyCompatibilityFixes).observe(document.documentElement, {
                        childList: true,
                        subtree: true
                    });
                    applyCompatibilityFixes();
                })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(compatibilityScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.keyboardDismissMode = .interactive

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
