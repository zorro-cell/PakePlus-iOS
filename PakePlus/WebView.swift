import SafariServices
import SwiftUI
import UIKit

/// Uses Apple's secure browser container so Google OAuth is not loaded inside
/// a disallowed WKWebView embedded user-agent.
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
