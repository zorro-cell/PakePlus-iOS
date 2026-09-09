const { execSync } = require('child_process')
const fs = require('fs-extra')
const plist = require('plist')
const path = require('path')
const ppconfig = require('./ppconfig.json')

const updateAppName = async (appName) => {
    // workerflow build app showName
    try {
        const plistPath = path.join(__dirname, '../PakePlus/Info.plist')
        execSync(
            `plutil -replace CFBundleDisplayName -string "${appName}" "${plistPath}"`
        )
        // await fs.writeFile(projectPbxprojPath, content)
        console.log(`✅ Updated app_name to: ${appName}`)
    } catch (error) {
        console.error('❌ Error updating app name:', error)
    }
}

// update ContentView.swift
const updateContentView = async (safeArea) => {
    try {
        // Assuming ContentView.swift
        const contentViewPath = path.join(
            __dirname,
            '../PakePlus/ContentView.swift'
        )
        let content = await fs.readFile(contentViewPath, 'utf8')
        if (safeArea === 'all') {
            console.log('safeArea is all')
        } else if (safeArea === 'top') {
            console.log('safeArea is top')
            content = content.replace(
                /edges: \[\]/,
                `edges: [.leading, .trailing, .bottom]`
            )
        } else if (safeArea === 'bottom') {
            console.log('safeArea is bottom')
            content = content.replace(
                /edges: \[\]/,
                `edges: [.top, .leading, .trailing]`
            )
        } else if (safeArea === 'left') {
            console.log('safeArea is left')
            content = content.replace(
                /edges: \[\]/,
                `edges: [.top, .trailing, .bottom]`
            )
        } else if (safeArea === 'right') {
            console.log('safeArea is right')
            content = content.replace(
                /edges: \[\]/,
                `edges: [.top, .leading, .bottom]`
            )
        } else if (safeArea === 'horizontal') {
            console.log('safeArea is horizontal')
            content = content.replace(/edges: \[\]/, `edges: [.top, .bottom]`)
        } else if (safeArea === 'vertical') {
            console.log('safeArea is vertical')
            content = content.replace(
                /edges: \[\]/,
                `edges: [.leading, .trailing]`
            )
        }
        await fs.writeFile(contentViewPath, content)
        console.log(`✅ Updated safeArea to: ${safeArea}`)
    } catch (error) {
        console.error('❌ Error updating safeArea:', error)
    }
}

const updateWebEnv = async (webview) => {
    // update debug
    const webViewPath = path.join(__dirname, '../PakePlus/WebView.swift')
    let content = await fs.readFile(webViewPath, 'utf8')
    content = content.replace(/let debug = false/, `let debug = ${debug}`)

    // update userAgent
    const { userAgent } = webview
    if (userAgent) {
        content = content.replace(
            `// webView.customUserAgent = ""`,
            `webView.customUserAgent = "${userAgent}"`
        )
    }

    await fs.writeFile(webViewPath, content)
    console.log(`✅ Updated debug to: ${debug}`)
}

// set github env
const setGithubEnv = (
    name,
    version,
    pubBody,
    isHtml,
    artifactName,
    bundleId,
    buildNumber
) => {
    console.log('setGithubEnv......')
    const envPath = process.env.GITHUB_ENV
    if (!envPath) {
        console.error('GITHUB_ENV is not defined')
        return
    }
    try {
        const entries = {
            NAME: name,
            VERSION: version,
            PUBBODY: pubBody,
            ISHTML: isHtml,
            ARTIFACT_NAME: artifactName,
            BUNDLE_ID: bundleId,
            BUILD_NUMBER: buildNumber,
        }
        for (const [key, value] of Object.entries(entries)) {
            if (value !== undefined) {
                fs.appendFileSync(envPath, `${key}=${value}\n`)
            }
        }
        console.log('✅ Environment variables written to GITHUB_ENV')
        console.log(fs.readFileSync(envPath, 'utf-8'))
    } catch (err) {
        console.error('❌ Failed to parse config or write to GITHUB_ENV:', err)
    }
    console.log('setGithubEnv success')
}

// update pppwd.html
const updatePPPwdHtml = (
    startMethod,
    startPwd,
    pwdTitle,
    pwdBtn,
    pwdPlace,
    pwdTip,
    pwdError,
    pwdStyle,
    pwdTheme,
    webUrl,
    isHtml
) => {
    console.log('updatePPPwdHtml......')
    const indexHtmlPath = path.join(__dirname, './www/pppwd.html')
    const indexHtml = fs.readFileSync(indexHtmlPath, 'utf-8')
    const targetUrl = isHtml ? './index.html' : webUrl
    const newIndexHtml = indexHtml
        .replaceAll('startMethod', startMethod)
        .replaceAll('startPwd', startPwd || '123456')
        .replaceAll('pwdTitle', pwdTitle || '请输入密码')
        .replaceAll('pwdBtn', pwdBtn || '验证')
        .replaceAll('pwdPlace', pwdPlace || '')
        .replaceAll('pwdTip', pwdTip || '')
        .replaceAll('pwdError', pwdError || '密码错误')
        .replaceAll('pwdStyle', pwdStyle || 'flat')
        .replaceAll('pwdTheme', pwdTheme || 'dark')
        .replaceAll('https://pakeplus.com/', targetUrl)
    fs.writeFileSync(indexHtmlPath, newIndexHtml)
    console.log('updatePPPwdHtml success')
}

// update ios applicationId
const updateProject = async (
    newBundleId,
    showName,
    direction = 'default',
    version,
    buildNumber
) => {
    // Write back only if changes were made
    const pbxprojPath = path.join(
        __dirname,
        '../PakePlus.xcodeproj/project.pbxproj'
    )
    try {
        console.log(`Updating Bundle ID to ${newBundleId}...`)
        let content = fs.readFileSync(pbxprojPath, 'utf8')
        // update bundleId
        content = content.replaceAll(
            /PRODUCT_BUNDLE_IDENTIFIER = (.*?);/g,
            `PRODUCT_BUNDLE_IDENTIFIER = ${newBundleId};`
        )
        content = content.replaceAll(
            /MARKETING_VERSION = (.*?);/g,
            `MARKETING_VERSION = ${version};`
        )
        content = content.replaceAll(
            /CURRENT_PROJECT_VERSION = (.*?);/g,
            `CURRENT_PROJECT_VERSION = ${buildNumber};`
        )
        // clear project.pbxproj DisplayName
        console.log(`Updating Display Name to ${showName}...`)
        content = content.replaceAll(
            /INFOPLIST_KEY_CFBundleDisplayName = (.*?);/g,
            ''
        )
        // content = content.replaceAll(
        //     /INFOPLIST_KEY_CFBundleDisplayName = (.*?);/g,
        //     `INFOPLIST_KEY_CFBundleDisplayName = ${showName};`
        // )
        // update direction
        if (direction === 'default') {
            content = content.replaceAll(
                /INFOPLIST_KEY_UISupportedInterfaceOrientations = (.*?);/g,
                `INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortrait";`
            )
        } else if (direction === 'vertical') {
            content = content.replaceAll(
                /INFOPLIST_KEY_UISupportedInterfaceOrientations = (.*?);/g,
                `INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait";`
            )
        } else if (direction === 'horizontal') {
            content = content.replaceAll(
                /INFOPLIST_KEY_UISupportedInterfaceOrientations = (.*?);/g,
                `INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";`
            )
        } else {
            console.log('❌ Invalid direction:', direction)
        }
        // update
        fs.writeFileSync(pbxprojPath, content)
        console.log(`✅ Updated project success`)
    } catch (error) {
        console.error('Error updating Bundle ID:', error)
    }
}

// parse Info.plist and update Info.plist
const updateInfoPlist = async (
    showName,
    debug,
    webUrl,
    isHtml,
    safeArea,
    userAgent,
    launchImage,
    screenOn,
    startMethod
) => {
    const infoPlistPath = path.join(__dirname, '../PakePlus/Info.plist')
    const infoPlist = fs.readFileSync(infoPlistPath, 'utf8')
    const infoPlistData = plist.parse(infoPlist)
    // update showName
    infoPlistData.CFBundleDisplayName = showName
    // is html
    if (startMethod === 'password' || startMethod === 'oncePwd') {
        infoPlistData.WEBURL = 'https://www.password.com/'
        fs.copySync(
            path.join(__dirname, './www'),
            path.join(__dirname, '../PakePlus')
        )
        console.log(`📦 HTML copied to PakePlus`)
    } else if (isHtml) {
        infoPlistData.WEBURL = 'https://www.pakeplus.com/'
        fs.copySync(
            path.join(__dirname, './www'),
            path.join(__dirname, '../PakePlus')
        )
        console.log(`📦 HTML copied to PakePlus`)
    } else {
        infoPlistData.WEBURL = webUrl
        // remove index.html
        fs.unlinkSync(path.join(__dirname, '../PakePlus/index.html'))
    }
    // update debug
    if (debug) {
        infoPlistData.DEBUG = debug
    } else {
        // remove vConsole.js
        fs.unlinkSync(path.join(__dirname, '../PakePlus/vConsole.js'))
    }
    // update userAgent
    if (userAgent) {
        infoPlistData.USERAGENT = userAgent
    } else {
        infoPlistData.USERAGENT = ''
    }
    // update fullScreen
    if (safeArea === 'fullscreen') {
        infoPlistData.FULLSCREEN = true
    } else {
        infoPlistData.FULLSCREEN = false
    }
    // update launchImage
    if (launchImage) {
        infoPlistData.LAUNCHIMAGE = true
        console.log('config LaunchScreen...')
        // copy launchImage to LaunchScreen.imageset
        const launchPath = path.join(__dirname, '../launch.jpg')
        const launchImagePath = path.join(
            __dirname,
            '../PakePlus/Assets.xcassets/LaunchScreen.imageset/launch.jpg'
        )
        fs.copyFileSync(launchPath, launchImagePath)
        console.log('✅ Copied launchImage to LaunchScreen.imageset')
    } else {
        infoPlistData.LAUNCHIMAGE = false
        // delete LaunchScreen.imageset
        fs.rmSync(
            path.join(
                __dirname,
                '../PakePlus/Assets.xcassets/LaunchScreen.imageset'
            ),
            { recursive: true, force: true }
        )
        console.log('remove LaunchScreen...')
    }
    // update screenOn
    if (screenOn) {
        infoPlistData.SCREENON = true
    } else {
        infoPlistData.SCREENON = false
    }
    // log
    console.log('new infoPlist: ', infoPlistData)
    fs.writeFileSync(infoPlistPath, plist.build(infoPlistData))
}

const main = async () => {
    const {
        webview,
        launchImage,
        screenOn,
        direction,
        startMethod,
        startPwd,
        pwdTitle,
        pwdBtn,
        pwdPlace,
        pwdTip,
        pwdError,
        pwdStyle,
        pwdTheme,
    } = ppconfig.phone

    const {
        name,
        showName,
        version,
        webUrl,
        id,
        artifactName,
        buildNumber,
        pubBody,
        debug,
        safeArea,
        isHtml,
    } = ppconfig.ios

    // Update app name if provided
    // await updateAppName(showName)

    // Update web URL if provided
    await updateContentView(safeArea)

    // update pppwd.html
    updatePPPwdHtml(
        startMethod,
        startPwd,
        pwdTitle,
        pwdBtn,
        pwdPlace,
        pwdTip,
        pwdError,
        pwdStyle,
        pwdTheme,
        webUrl,
        isHtml
    )

    // update ios applicationId
    await updateProject(id, showName, direction, version, buildNumber)

    // set github env
    setGithubEnv(
        name,
        version,
        pubBody,
        isHtml,
        artifactName,
        id,
        buildNumber
    )

    // parse Info.plist and update baseUrl
    const userAgent = webview.userAgent
    // update Info.plist
    await updateInfoPlist(
        showName,
        debug,
        webUrl,
        isHtml,
        safeArea,
        userAgent,
        launchImage,
        screenOn,
        startMethod
    )
    // success
    console.log('✅ Worker Success')
}

// run
;(async () => {
    try {
        console.log('🚀 worker start')
        await main()
        console.log('🚀 worker end')
    } catch (error) {
        console.error('❌ Worker Error:', error)
    }
})()
