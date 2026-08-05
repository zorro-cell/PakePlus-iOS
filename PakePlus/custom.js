// very important, if you don't know what it is, don't touch it
// 非常重要，不懂代码不要动，这里可以解决80%的问题，也可以生产1000+的bug

// WKWebView does not implement the Web Speech API. Provide the browser-shaped
// interface expected by Hermes and forward recognition to the native iOS bridge.
;(() => {
    const instances = new Map()
    let nextInstanceId = 1

    class HermesSpeechRecognition extends EventTarget {
        constructor() {
            super()
            this.lang = 'zh-CN'
            this.continuous = false
            this.interimResults = false
            this.maxAlternatives = 1
            this.onstart = null
            this.onresult = null
            this.onerror = null
            this.onend = null
            this.onaudiostart = null
            this.onaudioend = null
            this.onspeechstart = null
            this.onspeechend = null
            this.__instanceId = `hermes_speech_${nextInstanceId++}`
            this.__active = false
            instances.set(this.__instanceId, this)
        }

        start() {
            if (this.__active) {
                const error = new DOMException('Recognition has already started', 'InvalidStateError')
                throw error
            }
            const bridge = window.webkit?.messageHandlers?.speechBridge
            if (!bridge) {
                this.__dispatchError('service-not-allowed', 'iOS speech bridge is unavailable')
                this.__dispatchEnd()
                return
            }
            this.__active = true
            bridge.postMessage({
                action: 'start',
                instanceId: this.__instanceId,
                lang: this.lang || 'zh-CN',
                continuous: Boolean(this.continuous),
                interimResults: Boolean(this.interimResults),
            })
        }

        stop() {
            if (!this.__active) return
            window.webkit?.messageHandlers?.speechBridge?.postMessage({
                action: 'stop',
                instanceId: this.__instanceId,
            })
        }

        abort() {
            if (!this.__active) return
            window.webkit?.messageHandlers?.speechBridge?.postMessage({
                action: 'abort',
                instanceId: this.__instanceId,
            })
        }

        __dispatch(name, event = {}) {
            const domEvent = new Event(name)
            Object.entries(event).forEach(([key, value]) => {
                if (key !== 'type') Object.defineProperty(domEvent, key, { value, enumerable: true })
            })
            const handler = this[`on${name}`]
            if (typeof handler === 'function') handler.call(this, domEvent)
            this.dispatchEvent(domEvent)
        }

        __dispatchError(error, message) {
            this.__dispatch('error', { type: 'error', error, message })
        }

        __dispatchEnd() {
            this.__active = false
            this.__dispatch('end', { type: 'end' })
        }
    }

    window.__hermesSpeechBridgeReceive = (payload) => {
        const recognition = instances.get(payload?.instanceId)
        if (!recognition) return
        switch (payload.type) {
            case 'start':
                recognition.__dispatch('start', { type: 'start' })
                recognition.__dispatch('audiostart', { type: 'audiostart' })
                recognition.__dispatch('speechstart', { type: 'speechstart' })
                break
            case 'result': {
                if (!recognition.interimResults && !payload.isFinal) return
                const alternative = {
                    transcript: String(payload.transcript || ''),
                    confidence: Number(payload.confidence ?? 1),
                }
                const result = [alternative]
                result.isFinal = Boolean(payload.isFinal)
                const results = [result]
                recognition.__dispatch('result', {
                    type: 'result',
                    resultIndex: 0,
                    results,
                })
                break
            }
            case 'error':
                recognition.__dispatchError(payload.error || 'network', payload.message || '')
                break
            case 'end':
                recognition.__dispatch('speechend', { type: 'speechend' })
                recognition.__dispatch('audioend', { type: 'audioend' })
                recognition.__dispatchEnd()
                break
        }
    }

    // Override WebKit's exposed stub as well as fill the unprefixed API.
    const installSpeechConstructor = (name) => {
        try {
            Object.defineProperty(window, name, {
                configurable: true,
                writable: true,
                value: HermesSpeechRecognition,
            })
        } catch (_) {
            try { window[name] = HermesSpeechRecognition } catch (_) {}
        }
    }
    installSpeechConstructor('SpeechRecognition')
    installSpeechConstructor('webkitSpeechRecognition')
})()

const __pp_isBlobUrl = (url) =>
    typeof url === 'string' && url.startsWith('blob:')

const __pp_guessExtFromMime = (mime) => {
    const m = (mime || '').toLowerCase()
    const map = {
        'application/pdf': 'pdf',
        'image/png': 'png',
        'image/jpeg': 'jpg',
        'image/gif': 'gif',
        'image/webp': 'webp',
        'text/plain': 'txt',
        'application/json': 'json',
        'application/zip': 'zip',
        'application/octet-stream': 'bin',
    }
    return map[m] || ''
}

const __pp_readBlobAsBase64 = (blob) =>
    new Promise((resolve, reject) => {
        const reader = new FileReader()
        reader.onload = () => {
            const result = reader.result || ''
            const comma = result.indexOf(',')
            resolve(comma >= 0 ? result.slice(comma + 1) : result)
        }
        reader.onerror = () =>
            reject(reader.error || new Error('read blob failed'))
        reader.readAsDataURL(blob)
    })

const __pp_downloadBlobViaBridge = async (href, filename) => {
    const handler = window?.webkit?.messageHandlers?.blobDownload
    if (!handler) return false

    const id = `pp_${Date.now()}_${Math.random().toString(16).slice(2)}`
    try {
        // blob: 只能在页面上下文读取
        const res = await fetch(href)
        const blob = await res.blob()

        let name = filename || 'download'
        const ext = __pp_guessExtFromMime(blob.type)
        if (ext && !name.toLowerCase().endsWith(`.${ext}`)) {
            name = `${name}.${ext}`
        }

        // 2MB 分片，避免单次 postMessage 过大
        const chunkSize = 2 * 1024 * 1024
        const total = Math.max(1, Math.ceil(blob.size / chunkSize))

        handler.postMessage({
            action: 'start',
            id,
            filename: name,
            mimeType: blob.type || '',
            size: blob.size || 0,
            totalChunks: total,
        })

        for (let i = 0; i < total; i++) {
            const part = blob.slice(
                i * chunkSize,
                Math.min(blob.size, (i + 1) * chunkSize)
            )
            const base64 = await __pp_readBlobAsBase64(part)
            handler.postMessage({
                action: 'chunk',
                id,
                index: i,
                totalChunks: total,
                data: base64,
            })
        }

        handler.postMessage({ action: 'finish', id })
        return true
    } catch (err) {
        try {
            handler.postMessage({
                action: 'error',
                id,
                message: String(err && err.message ? err.message : err),
            })
        } catch (_) {}
        return false
    }
}

const hookClick = (e) => {
    const origin = e.target.closest('a')
    const isBaseTargetBlank = document.querySelector(
        'head base[target="_blank"]'
    )
    if (!origin || !origin.href) return

    // 1) 支持 blob: 下载：交给 iOS 侧保存，避免 Web 侧弹二次授权/下载失败
    if (__pp_isBlobUrl(origin.href)) {
        e.preventDefault()
        __pp_downloadBlobViaBridge(
            origin.href,
            origin.getAttribute('download') || origin.download
        ).then((ok) => {
            // bridge 不可用或失败：降级为原始行为
            if (!ok) location.href = origin.href
        })
        return
    }

    // 2) 原有逻辑：拦截 _blank / base[target=_blank]
    if (origin.target === '_blank' || isBaseTargetBlank) {
        e.preventDefault()
        location.href = origin.href
    }
}

window.open = function (url, target, features) {
    console.log('open', url, target, features)
    location.href = url
}

document.addEventListener('click', hookClick, { capture: true })
