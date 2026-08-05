//
//  WebView.swift
//  PakePlus
//
//  Created by Song on 2025/3/30.
//

import AVFoundation
import CoreLocation
import Speech
import SwiftUI
import UserNotifications
import WebKit

struct WebView: UIViewRepresentable {
    // wkwebview url
    let webUrl: URL
    // is debug
    let debug: Bool
    // on load finished
    let onLoadFinished: (() -> Void)?
    // userAgent
    let userAgent = Bundle.main.object(forInfoDictionaryKey: "USERAGENT") as? String ?? ""

    func makeUIView(context: Context) -> WKWebView {
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        webConfiguration.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        webConfiguration.allowsInlineMediaPlayback = true
        webConfiguration.allowsPictureInPictureMediaPlayback = true
        webConfiguration.ignoresViewportScaleLimits = true
        webConfiguration.allowsInlineMediaPlayback = true
        webConfiguration.allowsAirPlayForMediaPlayback = true
        webConfiguration.allowsPictureInPictureMediaPlayback = true
        webConfiguration.selectionGranularity = .character
        // enable developer extras
        if #available(iOS 16.4, *) {
            webConfiguration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        } else {
            webConfiguration.preferences.setValue(true, forKey: "developerExtrasEnabled")
            UserDefaults.standard.set(true, forKey: "WebKitDeveloperExtras")
        }
        // creat wkwebview
        let webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        // transparent background
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // JS bridge: blob download
        webView.configuration.userContentController.add(context.coordinator, name: "blobDownload")
        webView.configuration.userContentController.add(context.coordinator, name: "hermesTaskCompleted")
        webView.configuration.userContentController.add(context.coordinator, name: "speechBridge")
        context.coordinator.webView = webView

        // Observe Hermes SSE/fetch streaming and use DOM-idle detection as a fallback.
        let completionScript = WKUserScript(
            source: WebView.hermesCompletionScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(completionScript)
        context.coordinator.prepareNotificationAuthorization()

        // debug script
        if debug, let debugScript = WebView.loadJSFile(named: "vConsole") {
            let fullScript = debugScript + "\nvar vConsole = new window.VConsole();"
            let userScript = WKUserScript(
                source: fullScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            webView.configuration.userContentController.addUserScript(userScript)
            if #available(iOS 16.4, *) {
                webView.isInspectable = true
            }
        }
        // config userAgent
        if !userAgent.isEmpty {
            webView.customUserAgent = userAgent
        }

        // Use one standard viewport element; the native background alone fills safe areas.
        let scriptInjection = WKUserScript(
            source: WebView.standardViewportScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        webView.configuration.userContentController.addUserScript(scriptInjection)

        // load custom script
        if let customScript = WebView.loadJSFile(named: "custom") {
            let userScript = WKUserScript(
                source: customScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            webView.configuration.userContentController.addUserScript(userScript)
        }

        if webUrl.host?.contains("pakeplus.com") == true {
            // load html file
            if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            }
        } else if webUrl.host?.contains("password.com") == true {
            if let url = Bundle.main.url(forResource: "pppwd", withExtension: "html") {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            }
        } else {
            // load url
            webView.load(URLRequest(url: webUrl))
        }

        // delegate 设置

        // Add gesture recognizers
        let rightSwipeGesture = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRightSwipe(_:)))
        rightSwipeGesture.direction = .right
        webView.addGestureRecognizer(rightSwipeGesture)

        let leftSwipeGesture = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLeftSwipe(_:)))
        leftSwipeGesture.direction = .left
        webView.addGestureRecognizer(leftSwipeGesture)

        context.coordinator.prepareWebGeolocationAuthorization()

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    // add coordinator to prevent zoom
    func makeCoordinator() -> Coordinator {
        Coordinator(onLoadFinished: onLoadFinished)
    }
}

// swifui coordinator
class Coordinator: NSObject, UIScrollViewDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
    private let onLoadFinished: (() -> Void)?
    private var didFinishMainFrameOnce = false
    private var locationManager: CLLocationManager?
    weak var webView: WKWebView?

    // Native speech-recognition state used by the injected Web Speech compatible bridge.
    private let speechAudioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var speechTask: SFSpeechRecognitionTask?
    private var speechInstanceID: String?
    private var speechIsStopping = false
    private var speechTapInstalled = false

    // init
    init(onLoadFinished: (() -> Void)?) {
        self.onLoadFinished = onLoadFinished
        super.init()
    }

    // blob download state
    private struct BlobDownloadState {
        var filename: String
        var mimeType: String
        var totalChunks: Int
        var receivedChunkIndexes: Set<Int>
        var buffer: Data
    }

    // blob downloads
    private var blobDownloads: [String: BlobDownloadState] = [:]

    // disable zoom
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        // disable zoom
        return nil
    }

    // Handle right swipe gesture
    @objc func handleRightSwipe(_ gesture: UISwipeGestureRecognizer) {
        if let webView = gesture.view as? WKWebView, webView.canGoBack {
            webView.goBack()
        }
    }

    // Handle left swipe gesture
    @objc func handleLeftSwipe(_ gesture: UISwipeGestureRecognizer) {
        if let webView = gesture.view as? WKWebView, webView.canGoForward {
            webView.goForward()
        }
    }

    // MARK: - WKNavigationDelegate

    // intercept navigation, recognize common file types and trigger download
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // handle special schemes (tel/mailto/sms/etc.) by handing off to system.
        // Note: some pages trigger these via JS (location.href/window.open), which becomes `.other` instead of `.linkActivated`.
        if let scheme = url.scheme?.lowercased(),
           isExternalAppScheme(scheme)
        {
            decisionHandler(.cancel)
            openExternalURL(url)
            return
        }

        // only trigger download when user clicks link, other navigation load normally
        if navigationAction.navigationType == .linkActivated, shouldDownload(url: url) {
            decisionHandler(.cancel)
            downloadFile(from: url)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // only respond to main frame, and only trigger once, avoid iframe / multiple redirects causing repeated hiding
        guard !didFinishMainFrameOnce else { return }
        didFinishMainFrameOnce = true

        DispatchQueue.main.async { [onLoadFinished] in
            onLoadFinished?()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // avoid certain loading failures causing it to stay on the launch screen/loading
        guard !didFinishMainFrameOnce else { return }
        didFinishMainFrameOnce = true

        DispatchQueue.main.async { [onLoadFinished] in
            onLoadFinished?()
        }
    }

    // MARK: - WKUIDelegate: system vs web permissions

    /// 摄像头 / 麦克风：系统层已授权则直接 `.grant`（不再出现网页内二次权限面板）；系统已拒绝或受限则 `.deny`；尚未决定则 `.prompt`。
    /// 网页地理定位 `navigator.geolocation`：公开 `WKUIDelegate` 无对应决策方法，无法像媒体这样 `.grant`；仅能通过 `NSLocationWhenInUseUsageDescription` 与 `prepareWebGeolocationAuthorization()` 尽早完成系统层授权。
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void)
    {
        decisionHandler(permissionDecisionForMediaCapture(type: type))
    }

    @available(iOS 15.0, *)
    private func permissionDecisionForMediaCapture(type: WKMediaCaptureType) -> WKPermissionDecision {
        let video = AVCaptureDevice.authorizationStatus(for: .video)
        let audio = AVCaptureDevice.authorizationStatus(for: .audio)

        let authorized: Bool
        let deniedOrRestricted: Bool
        switch type {
        case .camera:
            authorized = video == .authorized
            deniedOrRestricted = video == .denied || video == .restricted
        case .microphone:
            authorized = audio == .authorized
            deniedOrRestricted = audio == .denied || audio == .restricted
        case .cameraAndMicrophone:
            authorized = video == .authorized && audio == .authorized
            deniedOrRestricted = video == .denied || video == .restricted || audio == .denied || audio == .restricted
        @unknown default:
            return .prompt
        }

        if authorized { return .grant }
        if deniedOrRestricted { return .deny }
        return .prompt
    }

    /// 在宿主侧请求「使用期间」定位授权，供 WKWebView 内 Geolocation API 使用（需配合 `NSLocationWhenInUseUsageDescription`）。
    func prepareWebGeolocationAuthorization() {
        guard locationManager == nil else { return }
        let manager = CLLocationManager()
        manager.delegate = self
        locationManager = manager
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse, .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    // MARK: - WKScriptMessageHandler (blob download bridge)

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "hermesTaskCompleted" {
            postTaskCompletionNotification()
            return
        }

        if message.name == "speechBridge" {
            handleSpeechBridgeMessage(message.body)
            return
        }

        guard message.name == "blobDownload" else { return }
        guard let body = message.body as? [String: Any] else { return }

        let action = (body["action"] as? String) ?? ""
        let id = (body["id"] as? String) ?? ""
        if id.isEmpty { return }

        switch action {
        case "start":
            let filename = sanitizeFilename((body["filename"] as? String) ?? "download")
            let mimeType = (body["mimeType"] as? String) ?? ""
            let totalChunks = max(1, (body["totalChunks"] as? Int) ?? 1)
            blobDownloads[id] = BlobDownloadState(
                filename: filename,
                mimeType: mimeType,
                totalChunks: totalChunks,
                receivedChunkIndexes: [],
                buffer: Data()
            )
            showDownloadStartedHint()

        case "chunk":
            guard var state = blobDownloads[id] else { return }
            guard let index = body["index"] as? Int else { return }
            guard let base64 = body["data"] as? String else { return }

            // prevent duplicate chunk
            if state.receivedChunkIndexes.contains(index) { return }
            guard let chunkData = Data(base64Encoded: base64) else { return }

            state.buffer.append(chunkData)
            state.receivedChunkIndexes.insert(index)
            blobDownloads[id] = state

        case "finish":
            guard let state = blobDownloads[id] else { return }
            blobDownloads.removeValue(forKey: id)

            // only save when all chunks are received
            guard state.receivedChunkIndexes.count >= state.totalChunks else { return }
            saveAndShareBlobData(state.buffer, filename: state.filename)

        case "error":
            blobDownloads.removeValue(forKey: id)
            if let msg = body["message"] as? String, !msg.isEmpty {
                print("blob download failed: \(msg)")
            }

        default:
            return
        }
    }

    // MARK: - Native Speech bridge

    private func handleSpeechBridgeMessage(_ messageBody: Any) {
        guard let body = messageBody as? [String: Any] else { return }
        let action = (body["action"] as? String) ?? ""
        let instanceID = (body["instanceId"] as? String) ?? ""
        guard !instanceID.isEmpty else { return }

        switch action {
        case "start":
            let language = ((body["lang"] as? String) ?? "zh-CN").trimmingCharacters(in: .whitespacesAndNewlines)
            requestSpeechPermissionsAndStart(instanceID: instanceID, language: language.isEmpty ? "zh-CN" : language)
        case "stop":
            guard speechInstanceID == instanceID else { return }
            stopSpeechRecognition(abort: false)
        case "abort":
            guard speechInstanceID == instanceID else { return }
            stopSpeechRecognition(abort: true)
        default:
            break
        }
    }

    private func requestSpeechPermissionsAndStart(instanceID: String, language: String) {
        if speechInstanceID != nil {
            stopSpeechRecognition(abort: true)
        }
        speechInstanceID = instanceID
        speechIsStopping = false

        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            DispatchQueue.main.async {
                guard let self, self.speechInstanceID == instanceID else { return }
                guard speechStatus == .authorized else {
                    self.finishSpeechRecognition(error: "not-allowed", message: "语音识别权限未开启")
                    return
                }

                AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                    DispatchQueue.main.async {
                        guard let self, self.speechInstanceID == instanceID else { return }
                        guard granted else {
                            self.finishSpeechRecognition(error: "not-allowed", message: "麦克风权限未开启")
                            return
                        }
                        self.startSpeechRecognition(instanceID: instanceID, language: language)
                    }
                }
            }
        }
    }

    private func startSpeechRecognition(instanceID: String, language: String) {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        guard let recognizer, recognizer.isAvailable else {
            finishSpeechRecognition(error: "network", message: "Apple 语音识别服务暂不可用")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if #available(iOS 16.0, *) {
                request.addsPunctuation = true
            }

            let inputNode = speechAudioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                finishSpeechRecognition(error: "audio-capture", message: "麦克风音频格式不可用")
                return
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }
            speechTapInstalled = true

            speechRecognizer = recognizer
            speechRequest = request
            speechAudioEngine.prepare()
            try speechAudioEngine.start()
            emitSpeechEvent("start", instanceID: instanceID)

            speechTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self, self.speechInstanceID == instanceID else { return }
                    if let result {
                        let transcript = result.bestTranscription.formattedString
                        if !transcript.isEmpty {
                            self.emitSpeechResult(transcript, isFinal: result.isFinal, instanceID: instanceID)
                        }
                        if result.isFinal {
                            self.finishSpeechRecognition()
                            return
                        }
                    }
                    if let error, !self.speechIsStopping {
                        let nsError = error as NSError
                        let webError = nsError.code == 216 ? "aborted" : "network"
                        self.finishSpeechRecognition(error: webError, message: error.localizedDescription)
                    } else if error != nil {
                        self.finishSpeechRecognition()
                    }
                }
            }
        } catch {
            finishSpeechRecognition(error: "audio-capture", message: error.localizedDescription)
        }
    }

    private func stopSpeechRecognition(abort: Bool) {
        guard let instanceID = speechInstanceID else { return }
        speechIsStopping = true
        if speechAudioEngine.isRunning {
            speechAudioEngine.stop()
        }
        removeSpeechAudioTapIfNeeded()

        if abort {
            speechRequest?.endAudio()
            speechTask?.cancel()
            emitSpeechEvent("error", instanceID: instanceID, payload: [
                "error": "aborted",
                "message": "语音识别已取消"
            ])
            finishSpeechRecognition()
        } else {
            speechRequest?.endAudio()
        }
    }

    private func finishSpeechRecognition(error: String? = nil, message: String = "") {
        guard let instanceID = speechInstanceID else { return }
        if speechAudioEngine.isRunning {
            speechAudioEngine.stop()
        }
        removeSpeechAudioTapIfNeeded()
        speechRequest?.endAudio()
        speechTask?.cancel()
        speechRequest = nil
        speechTask = nil
        speechRecognizer = nil
        speechInstanceID = nil
        speechIsStopping = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if let error {
            emitSpeechEvent("error", instanceID: instanceID, payload: ["error": error, "message": message])
        }
        emitSpeechEvent("end", instanceID: instanceID)
    }

    private func removeSpeechAudioTapIfNeeded() {
        guard speechTapInstalled else { return }
        speechAudioEngine.inputNode.removeTap(onBus: 0)
        speechTapInstalled = false
    }

    private func emitSpeechResult(_ transcript: String, isFinal: Bool, instanceID: String) {
        emitSpeechEvent("result", instanceID: instanceID, payload: [
            "transcript": transcript,
            "isFinal": isFinal,
            "confidence": 1.0
        ])
    }

    private func emitSpeechEvent(_ type: String, instanceID: String, payload: [String: Any] = [:]) {
        var eventPayload = payload
        eventPayload["type"] = type
        eventPayload["instanceId"] = instanceID
        guard JSONSerialization.isValidJSONObject(eventPayload),
              let data = try? JSONSerialization.data(withJSONObject: eventPayload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.__hermesSpeechBridgeReceive(\(json));") { _, evaluationError in
            if let evaluationError {
                print("speech bridge callback failed: \(evaluationError.localizedDescription)")
            }
        }
    }

    // MARK: - Hermes task completion notifications

    func prepareNotificationAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("notification authorization failed: \(error.localizedDescription)")
            } else {
                print("notification authorization granted: \(granted)")
            }
        }
    }

    private func postTaskCompletionNotification() {
        let content = UNMutableNotificationContent()
        content.title = "hermes"
        content.body = "Hermes 已完成任务"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "hermes-task-complete-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("failed to schedule task notification: \(error.localizedDescription)")
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }

    private func sanitizeFilename(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "download" }
        // remove path separator, avoid writing file exception
        return trimmed
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    private func saveAndShareBlobData(_ data: Data, filename: String) {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let destinationURL = tempDir.appendingPathComponent(filename)

        try? fileManager.removeItem(at: destinationURL)
        do {
            try data.write(to: destinationURL, options: [.atomic])
        } catch {
            print("save blob file failed: \(error.localizedDescription)")
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.presentShareSheet(for: destinationURL)
        }
    }

    /// check if url is a common file type that needs to be downloaded
    private func shouldDownload(url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        if pathExtension.isEmpty {
            return false
        }

        let downloadableExtensions: Set<String> = [
            // 图片
            "png", "jpg", "jpeg", "gif", "bmp", "webp", "heic",
            // 视频
            "mp4", "mov", "m4v", "avi", "mkv",
            // 音频
            "mp3", "wav", "aac", "m4a", "flac",
            // 文本/文档
            "txt", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
            // 压缩
            "zip", "rar", "7z"
        ]

        return downloadableExtensions.contains(pathExtension)
    }

    private func isExternalAppScheme(_ scheme: String) -> Bool {
        switch scheme {
        case "tel", "mailto", "sms", "facetime", "facetime-audio":
            return true
        default:
            return false
        }
    }

    private func openExternalURL(_ url: URL) {
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    /// 使用 URLSession 下载文件并弹出系统分享面板，让用户保存到「文件」或其他 App
    private func downloadFile(from url: URL) {
        print("start downloading file: \(url.absoluteString)")
        showDownloadStartedHint()
        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
            if let error = error {
                print("download failed: \(error.localizedDescription)")
                return
            }

            guard let tempURL = tempURL else {
                print("download failed: temporary file not found")
                return
            }

            // get file name from response or URL
            let suggestedName = (response as? HTTPURLResponse)?
                .allHeaderFields["Content-Disposition"] as? String

            let fileName: String
            if let suggestedName,
               let range = suggestedName.range(of: "filename=")
            {
                let namePart = String(suggestedName[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "\"; "))
                fileName = namePart.isEmpty ? url.lastPathComponent : namePart
            } else {
                fileName = url.lastPathComponent.isEmpty ? "file" : url.lastPathComponent
            }

            let fileManager = FileManager.default
            let tempDir = fileManager.temporaryDirectory
            let destinationURL = tempDir.appendingPathComponent(fileName)

            // if file already exists, remove it
            try? fileManager.removeItem(at: destinationURL)

            do {
                try fileManager.moveItem(at: tempURL, to: destinationURL)
            } catch {
                print("failed to move download file: \(error.localizedDescription)")
                return
            }

            print("download finished, temporary save path: \(destinationURL.path)")

            DispatchQueue.main.async {
                self?.presentShareSheet(for: destinationURL)
            }
        }

        task.resume()
    }

    /// show "start downloading" hint (disappears after 2 seconds)
    private func showDownloadStartedHint() {
        DispatchQueue.main.async {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) else { return }

            let label = UILabel()
            label.text = "start downloading..."
            label.font = .systemFont(ofSize: 15, weight: .medium)
            label.textColor = .white
            label.backgroundColor = .systemBlue
            label.textAlignment = .center
            label.layer.cornerRadius = 8
            label.clipsToBounds = true
            label.alpha = 0

            let padding: CGFloat = 16
            let topMargin: CGFloat = 20
            label.sizeToFit()
            label.frame.size.width += padding * 2
            label.frame.size.height += padding
            let yCenter = window.safeAreaInsets.top + label.frame.height / 2 + topMargin
            label.center = CGPoint(x: window.bounds.midX, y: yCenter)

            window.addSubview(label)

            UIView.animate(withDuration: 0.25, animations: { label.alpha = 1 })
            UIView.animate(withDuration: 0.25, delay: 1.75, options: [], animations: { label.alpha = 0 }) { _ in
                label.removeFromSuperview()
            }
        }
    }

    // present system share sheet, user can choose to save to "file" or share to other apps
    private func presentShareSheet(for fileURL: URL) {
        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = UIApplication.shared.windows.first { $0.isKeyWindow }

        if let topVC = Coordinator.topViewController() {
            topVC.present(activityVC, animated: true, completion: nil)
        } else {
            print("top view controller not found, cannot show share sheet")
        }
    }

    // get current top view controller
    private static func topViewController(base: UIViewController? = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first(where: { $0.isKeyWindow })?.rootViewController) -> UIViewController?
    {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}

extension WebView {
    static let standardViewportScript = #"""
    (() => {
        const installViewport = () => {
            if (!document.head) {
                setTimeout(installViewport, 0);
                return;
            }
            const viewports = [...document.querySelectorAll('meta[name="viewport"]')];
            const meta = viewports.shift() || document.createElement('meta');
            meta.name = 'viewport';
            meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
            viewports.forEach((duplicate) => duplicate.remove());
            if (!meta.isConnected) document.head.appendChild(meta);
        };
        installViewport();
    })();
    """#

    static let hermesCompletionScript = #"""
    (() => {
        if (window.__hermesCompletionObserverInstalled) return;
        window.__hermesCompletionObserverInstalled = true;

        const bridge = window.webkit?.messageHandlers?.hermesTaskCompleted;
        let armed = false;
        let streamActive = 0;
        let sawResponseActivity = false;
        let lastActivityAt = 0;
        let lastNotificationAt = 0;
        let initialTextLength = 0;

        const now = () => Date.now();
        const arm = () => {
            armed = true;
            sawResponseActivity = false;
            lastActivityAt = now();
            initialTextLength = document.body?.innerText?.length || 0;
        };
        const notify = (reason) => {
            if (!armed || now() - lastNotificationAt < 5000) return;
            armed = false;
            streamActive = 0;
            lastNotificationAt = now();
            bridge?.postMessage({ reason, at: new Date().toISOString() });
        };
        const isDoneMarker = (text) =>
            /(?:^|\n)\s*(?:data:\s*)?(?:\[DONE\]|done)\s*(?:\n|$)/i.test(text) ||
            /"(?:type|event|status)"\s*:\s*"(?:done|complete|completed|message_stop|response\.completed)"/i.test(text);

        const nativeFetch = window.fetch?.bind(window);
        if (nativeFetch) {
            window.fetch = async (...args) => {
                const input = args[0];
                const init = args[1] || {};
                const method = String(init.method || input?.method || 'GET').toUpperCase();
                if (method !== 'GET') arm();
                const response = await nativeFetch(...args);
                const type = response.headers?.get('content-type') || '';
                if (/text\/event-stream/i.test(type) && response.body) {
                    streamActive += 1;
                    const clone = response.clone();
                    (async () => {
                        const reader = clone.body.getReader();
                        const decoder = new TextDecoder();
                        let tail = '';
                        try {
                            while (true) {
                                const { value, done } = await reader.read();
                                if (done) break;
                                const text = decoder.decode(value, { stream: true });
                                if (text) {
                                    sawResponseActivity = true;
                                    lastActivityAt = now();
                                    tail = (tail + text).slice(-4096);
                                    if (isDoneMarker(tail)) {
                                        notify('sse-done');
                                        return;
                                    }
                                }
                            }
                            if (sawResponseActivity) notify('fetch-stream-closed');
                        } catch (_) {
                            // The DOM fallback covers streams whose clone is cancelled.
                        } finally {
                            streamActive = Math.max(0, streamActive - 1);
                        }
                    })();
                }
                return response;
            };
        }

        const NativeEventSource = window.EventSource;
        if (NativeEventSource) {
            const WrappedEventSource = function(...args) {
                arm();
                const source = new NativeEventSource(...args);
                streamActive += 1;
                let gotData = false;
                source.addEventListener('message', (event) => {
                    gotData = true;
                    sawResponseActivity = true;
                    lastActivityAt = now();
                    if (isDoneMarker(String(event.data || ''))) notify('eventsource-done');
                });
                source.addEventListener('error', () => {
                    if (source.readyState === NativeEventSource.CLOSED) {
                        streamActive = Math.max(0, streamActive - 1);
                        if (gotData) notify('eventsource-closed');
                    }
                });
                return source;
            };
            WrappedEventSource.prototype = NativeEventSource.prototype;
            Object.defineProperties(WrappedEventSource, {
                CONNECTING: { value: NativeEventSource.CONNECTING },
                OPEN: { value: NativeEventSource.OPEN },
                CLOSED: { value: NativeEventSource.CLOSED }
            });
            window.EventSource = WrappedEventSource;
        }

        const markDomActivity = () => {
            if (!armed) return;
            sawResponseActivity = true;
            lastActivityAt = now();
        };
        const installDomFallback = () => {
            if (!document.documentElement) return setTimeout(installDomFallback, 50);
            new MutationObserver(markDomActivity).observe(document.documentElement, {
                childList: true,
                subtree: true,
                characterData: true
            });
            document.addEventListener('submit', arm, true);
            document.addEventListener('click', (event) => {
                const button = event.target?.closest?.('button');
                if (!button) return;
                const label = [button.innerText, button.getAttribute('aria-label'), button.title]
                    .filter(Boolean).join(' ');
                if (/(send|submit|发送|提交)/i.test(label) && !/(stop|停止|取消)/i.test(label)) arm();
            }, true);
            setInterval(() => {
                if (!armed || !sawResponseActivity || streamActive > 0) return;
                const textGrew = (document.body?.innerText?.length || 0) > initialTextLength;
                const stopControl = [...document.querySelectorAll('button')].some((button) => {
                    const label = [button.innerText, button.getAttribute('aria-label'), button.title]
                        .filter(Boolean).join(' ');
                    return /(stop|停止生成|停止响应|取消生成)/i.test(label);
                });
                if (textGrew && !stopControl && now() - lastActivityAt > 8000) notify('dom-idle');
            }, 2000);
        };
        installDomFallback();
    })();
    """#

    // load js file from bundle
    static func loadJSFile(named filename: String) -> String? {
        guard let path = Bundle.main.path(forResource: filename, ofType: "js") else {
            print("Could not find \(filename).js in bundle")
            return nil
        }

        do {
            let jsString = try String(contentsOfFile: path, encoding: .utf8)
            return jsString
        } catch {
            print("Error loading \(filename).js: \(error)")
            return nil
        }
    }
}
