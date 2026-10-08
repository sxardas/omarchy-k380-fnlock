import {modeLabel} from "./modes.mjs"

export const REFRESH = {min: 15, max: 3600, step: 15, value: 600}

export function refreshInterval(value) {
    const n = Number(value)
    if (value === undefined || value === null || value === "" || !isFinite(n)) return REFRESH.value
    const clamped = Math.max(REFRESH.min, Math.min(REFRESH.max, n))
    return REFRESH.min + Math.floor((clamped - REFRESH.min) / REFRESH.step) * REFRESH.step
}

// No JSON at all means the helper did not run: not built yet, or crashed.
export function parseStatus(raw) {
    try {
        const parsed = JSON.parse(String(raw || "").trim())
        if (parsed && typeof parsed === "object") return parsed
    } catch (e) {
    }
    return {found: true, error: "helper"}
}

export function isTransient(error) {
    return error === "not_found" || error === "timeout"
}

export function needsSetup(error) {
    return error === "permission" || error === "helper"
}

export function batteryOf(status, device) {
    if (status && status.battery && status.battery.percent !== undefined) return status.battery
    if (device && device.batteryAvailable) return {percent: Math.round(device.battery * 100), approximate: false}
    return null
}

export function batteryText(battery) {
    if (!battery || battery.percent === undefined || battery.percent === null) return ""
    return (battery.approximate ? "~" : "") + battery.percent + "%"
}

const ERRORS = {
    permission: hidraw => "No access to " + (hidraw || "hidraw") + ". Finish setup to install the udev rule.",
    not_found: () => "Connected, but its HID interface has not shown up yet.",
    timeout: () => "The keyboard did not answer. Press a key to wake it and retry.",
    unsupported: () => "This keyboard does not expose the HID++ Fn inversion feature.",
    disconnected: () => "The keyboard went away mid-request.",
    helper: () => "The helper is not built yet. Finish setup to build it and install the udev rule."
}

export function errorText(error, hidraw) {
    if (!error) return ""
    return ERRORS[error] ? ERRORS[error](hidraw) : "Keyboard error: " + error
}

export function statusTitle(s) {
    if (!s.loaded) return "Reading keyboard"
    if (needsSetup(s.error)) return "Setup needed"
    if (s.error && !s.mode) return "Not responding"
    return modeLabel(s.mode) + " keys"
}

export function tooltip(name, mode, battery) {
    const parts = [name]
    if (mode) parts.push(modeLabel(mode) + " keys")
    const bt = batteryText(battery)
    if (bt) parts.push(bt)
    return parts.join(" · ")
}
