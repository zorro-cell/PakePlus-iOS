const fs = require('fs')
const path = require('path')
const { execFileSync } = require('child_process')

const root = path.resolve(__dirname, '..')
const read = (relativePath) =>
    fs.readFileSync(path.join(root, relativePath), 'utf8')

const assert = (condition, message) => {
    if (!condition) throw new Error(message)
}

const config = JSON.parse(read('scripts/ppconfig.json'))
const ios = config.ios
const project = read('PakePlus.xcodeproj/project.pbxproj')
const plist = read('PakePlus/Info.plist')
const webView = read('PakePlus/WebView.swift')
const workflow = read('.github/workflows/build.yml')

const expected = {
    bundleId: 'com.zorrocell.chatgpt.ipad',
    phoneBundleId: 'com.zorrocell.chatgpt.webapp',
    version: '1.5.1',
    buildNumber: '7',
    artifactName: 'ChatGPT-iPad',
    userAgent:
        'Mozilla/5.0 (iPad; CPU OS 16_5_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1',
}

assert(ios.name === 'ChatGPT iPad', 'iOS release name must identify ChatGPT iPad')
assert(ios.showName === 'ChatGPT iPad', 'display name must identify ChatGPT iPad')
assert(ios.id === expected.bundleId, 'ppconfig bundle ID is not the iPad variant')
assert(ios.id !== expected.phoneBundleId, 'iPad bundle ID collides with the phone app')
assert(ios.version === expected.version, 'ppconfig iPad version is stale')
assert(ios.buildNumber === expected.buildNumber, 'ppconfig build number is stale')
assert(ios.artifactName === expected.artifactName, 'IPA artifact name is not explicit')
assert(ios.webUrl === 'https://chatgpt.com/', 'source must remain the ChatGPT web line')
assert(!JSON.stringify(ios).toLowerCase().includes('hermes'), 'iPad config drifted to the Hermes line')
assert(
    config.phone.webview.userAgent === expected.userAgent,
    'phone.webview user agent must target the requested iPadOS baseline'
)

assert(
    (project.match(/PRODUCT_BUNDLE_IDENTIFIER = [^;]+;/g) || []).length === 2,
    'expected Debug and Release bundle IDs'
)
assert(
    project.includes(`PRODUCT_BUNDLE_IDENTIFIER = ${expected.bundleId};`),
    'Xcode bundle ID is not the iPad variant'
)
assert(!project.includes(expected.phoneBundleId), 'Xcode project still contains the phone bundle ID')
assert(
    (project.match(/TARGETED_DEVICE_FAMILY = 2;/g) || []).length === 2,
    'Debug and Release must target iPad only'
)
assert(
    (project.match(new RegExp(`MARKETING_VERSION = ${expected.version.replaceAll('.', '\\.')};`, 'g')) || []).length === 2,
    'Debug and Release marketing versions are inconsistent'
)
assert(
    (project.match(new RegExp(`CURRENT_PROJECT_VERSION = ${expected.buildNumber};`, 'g')) || []).length === 2,
    'Debug and Release build numbers are inconsistent'
)
assert(
    (project.match(/INFOPLIST_KEY_UIRequiresFullScreen = NO;/g) || []).length === 2,
    'iPad multitasking metadata is missing'
)
assert(
    project.includes('INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown";'),
    'iPad orientation metadata is incomplete'
)

assert(plist.includes('<string>ChatGPT iPad</string>'), 'Info.plist display name is stale')
assert(plist.includes('<string>https://chatgpt.com/</string>'), 'Info.plist web URL is stale')
assert(plist.includes(`<string>${expected.userAgent}</string>`), 'Info.plist user agent is stale')

assert(webView.includes('viewport-fit=cover'), 'iPad viewport-fit handling is missing')
assert(webView.includes('keyboardDismissMode = .interactive'), 'keyboard dismissal handling is missing')
assert(webView.includes('scrollView.isScrollEnabled = true'), 'WKWebView scrolling is not explicitly enabled')
assert(webView.includes('scrollView.alwaysBounceVertical = true'), 'vertical WKWebView scrolling is not enabled')
assert(webView.includes('let nestedScrollScript = WKUserScript'), 'nested scroll compatibility script is missing')
assert(webView.includes('injectionTime: .atDocumentStart'), 'nested scroll script must run before ChatGPT layout')
assert(webView.includes('-webkit-overflow-scrolling: touch'), 'nested DOM momentum scrolling is missing')
assert(webView.includes('forMainFrameOnly: false'), 'nested scroll script must cover embedded web content')
assert(webView.includes('javaScriptCanOpenWindowsAutomatically = true'), 'OAuth popup support flag is missing')
assert(webView.includes('createWebViewWith configuration'), 'OAuth window delegate handling is missing')
assert(webView.includes(expected.userAgent), 'Swift Safari user agent fallback is stale')
assert(!webView.includes('iPhone; CPU'), 'iPhone-only user agent leaked into the iPad variant')

assert(workflow.includes('Build ChatGPT iPad IPA'), 'workflow identity is not explicit')
assert(workflow.includes('ARTIFACT_NAME'), 'workflow output name is not sourced explicitly')
assert(workflow.includes('derivedDataPath'), 'workflow build path is not deterministic')
assert(workflow.includes('upload-artifact@v4'), 'workflow does not publish a named IPA artifact')
assert(!workflow.includes('find ~/Library/Developer/Xcode/DerivedData'), 'workflow still uses an ambiguous app search')

try {
    execFileSync('plutil', ['-lint', path.join(root, 'PakePlus/Info.plist')], {
        stdio: 'pipe',
    })
} catch (error) {
    const output = error.stdout?.toString() || error.stderr?.toString() || error.message
    throw new Error(`Info.plist syntax check failed: ${output}`)
}

console.log('ChatGPT iPad static validation passed')
console.log(`bundle=${expected.bundleId} version=${expected.version} build=${expected.buildNumber}`)
