const DEFAULT_NAME = "Keyboard K380"

function isK380(device) {
    return !!device && [device.name, device.deviceName].some(n => /\bK380\b/i.test(String(n || "")))
}

// The configured address wins; otherwise the first paired K380, preferring
// a connected one so a second, sleeping K380 never shadows it.
export function findKeyboard(devices, address) {
    const wanted = String(address || "").toUpperCase()
    let fallback = null
    for (const d of devices || []) {
        if (!d) continue
        if (wanted) {
            if (String(d.address || "").toUpperCase() === wanted) return d
            continue
        }
        if (!isK380(d)) continue
        if (d.connected) return d
        if (!fallback) fallback = d
    }
    return fallback
}

export function deviceName(device) {
    return device ? device.name || device.deviceName || DEFAULT_NAME : DEFAULT_NAME
}

export function localPath(url) {
    return decodeURIComponent(String(url).replace(/^file:\/\//, ""))
}
