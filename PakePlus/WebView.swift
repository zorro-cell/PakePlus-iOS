import SafariServices
import SwiftUI
import UIKit

/// Grok's account service and third-party identity providers reject embedded
/// WKWebView authentication. The Safari controller remains the real browsing
/// context, while its browser chrome is placed outside the clipped container so
/// the app keeps an immersive appearance.
struct WebView: UIViewControllerRepresentable {
    let webUrl: URL
    let debug: Bool
    let onLoadFinished: (() -> Void)?

    func makeUIViewController(context: Context) -> CroppedSafariController {
        CroppedSafariController(url: webUrl, onLoadFinished: onLoadFinished)
    }

    func updateUIViewController(
        _ uiViewController: CroppedSafariController,
        context: Context
    ) {}
}

final class CroppedSafariController: UIViewController {
    private let safariController: SFSafariViewController
    private let onLoadFinished: (() -> Void)?

    // Standard compact iPhone Safari chrome is approximately 50 points at
    // each edge. The container clips those regions without touching the
    // secure browser session or its cookies.
    private let topChromeCrop: CGFloat = 50
    private let bottomChromeCrop: CGFloat = 50

    init(url: URL, onLoadFinished: (() -> Void)?) {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = false
        safariController = SFSafariViewController(
            url: url,
            configuration: configuration
        )
        self.onLoadFinished = onLoadFinished
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.clipsToBounds = true

        safariController.preferredBarTintColor = .black
        safariController.preferredControlTintColor = .white
        safariController.dismissButtonStyle = .close

        addChild(safariController)
        view.addSubview(safariController.view)
        safariController.didMove(toParent: self)

        DispatchQueue.main.async { [weak self] in
            self?.onLoadFinished?()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        safariController.view.frame = CGRect(
            x: 0,
            y: -topChromeCrop,
            width: view.bounds.width,
            height: view.bounds.height + topChromeCrop + bottomChromeCrop
        )
    }
}
