export const MEDIA = "media"
export const FUNCTION = "function"

export const KEYBOARD_ICON = "󰌌"

export const MODES = [
    {mode: MEDIA, label: "Media", short: "Media", icon: "󰝚"},
    {mode: FUNCTION, label: "Function", short: "Fn", icon: "󱊫"}
]

function find(mode) {
    return MODES.find(m => m.mode === mode) || null
}

export function normalizeMode(value) {
    const mode = String(value || "").toLowerCase()
    return find(mode) ? mode : ""
}

export function otherMode(mode) {
    return mode === MEDIA ? FUNCTION : MEDIA
}

export function modeLabel(mode) {
    const m = find(mode)
    return m ? m.label : ""
}

export function barIcon(mode) {
    return mode === FUNCTION ? find(FUNCTION).icon : KEYBOARD_ICON
}

export function barText(mode, withLabel) {
    const m = find(mode)
    return withLabel && m ? m.short + " " + barIcon(mode) : barIcon(mode)
}
