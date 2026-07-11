import SafariServices
import SwiftUI
import UIKit

/// Grok's account service and third-party identity providers reject embedded
/// WKWebView authentication. SFSafariViewController provides Apple's supported
/// secure browser context and keeps the complete sign-in redirect chain in one
/// persistent Safari session.
struct WebView: UIViewControllerRepresentable {
    let webUrl: URL
    let debug: Bool
    let onLoadFinished: (() -> Void)?

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = true

        let controller = SFSafariViewController(
            url: webUrl,
            configuration: configuration
        )
        controller.preferredBarTintColor = .black
        controller.preferredControlTintColor = .white
        controller.dismissButtonStyle = .close

        DispatchQueue.main.async {
            onLoadFinished?()
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: SFSafariViewController,
        context: Context
    ) {}
}
