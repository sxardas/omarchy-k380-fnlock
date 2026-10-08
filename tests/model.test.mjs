import test from "node:test"
import assert from "node:assert/strict"
import * as K from "../src/js/keyboard.mjs"
import * as M from "../src/js/modes.mjs"
import * as S from "../src/js/status.mjs"

test("modes", () => {
    assert.equal(M.normalizeMode("Media"), M.MEDIA)
    assert.equal(M.normalizeMode("FUNCTION"), M.FUNCTION)
    assert.equal(M.normalizeMode("fn"), "")
    assert.equal(M.otherMode(M.MEDIA), M.FUNCTION)
    assert.equal(M.otherMode(""), M.MEDIA)
    assert.equal(M.modeLabel(M.FUNCTION), "Function")
    assert.equal(M.barText(M.FUNCTION, true), "Fn 󱊫")
    assert.equal(M.barText(M.MEDIA, false), M.KEYBOARD_ICON)
})

test("the keyboard: configured address, else a connected K380", () => {
    const sleeping = {name: "Keyboard K380", address: "AA", connected: false}
    const awake = {deviceName: "K380 Multi-Device", address: "BB", connected: true}
    const mouse = {name: "MX Master", address: "CC", connected: true}
    assert.equal(K.findKeyboard([sleeping, mouse, awake], ""), awake)
    assert.equal(K.findKeyboard([sleeping, mouse], ""), sleeping)
    assert.equal(K.findKeyboard([sleeping, awake], "aa"), sleeping)
    assert.equal(K.findKeyboard([mouse], ""), null)
    assert.equal(K.deviceName(null), "Keyboard K380")
    assert.equal(K.localPath("file:///a%20b/bin/x"), "/a b/bin/x")
})

test("helper status", () => {
    assert.deepEqual(S.parseStatus(""), {found: true, error: "helper"})
    assert.equal(S.parseStatus('{"mode": "media"}').mode, "media")
    assert.ok(S.needsSetup("permission") && S.needsSetup("helper") && !S.needsSetup("timeout"))
    assert.ok(S.isTransient("not_found") && !S.isTransient("permission"))
    assert.equal(S.errorText("permission", "/dev/hidraw5"), "No access to /dev/hidraw5. Finish setup to install the udev rule.")
    assert.equal(S.errorText("weird"), "Keyboard error: weird")
    assert.equal(S.errorText(""), "")
})

test("battery: HID++ first, BlueZ as a fallback", () => {
    const hidpp = {percent: 90, approximate: false}
    assert.equal(S.batteryOf({battery: hidpp}, {batteryAvailable: true, battery: 0.5}), hidpp)
    assert.deepEqual(S.batteryOf({}, {batteryAvailable: true, battery: 0.5}), {percent: 50, approximate: false})
    assert.equal(S.batteryOf({}, {batteryAvailable: false}), null)
    assert.equal(S.batteryText({percent: 50, approximate: true}), "~50%")
    assert.equal(S.batteryText(null), "")
})

test("texts", () => {
    assert.equal(S.statusTitle({loaded: false}), "Reading keyboard")
    assert.equal(S.statusTitle({loaded: true, error: "helper"}), "Setup needed")
    assert.equal(S.statusTitle({loaded: true, error: "timeout", mode: ""}), "Not responding")
    assert.equal(S.statusTitle({loaded: true, error: "", mode: M.MEDIA}), "Media keys")
    assert.equal(S.tooltip("Keyboard K380", M.FUNCTION, {percent: 90}), "Keyboard K380 · Function keys · 90%")
})

test("refresh interval defaults, clamps and lands on its step", () => {
    assert.equal(S.refreshInterval(undefined), 600)
    assert.equal(S.refreshInterval("abc"), 600)
    assert.equal(S.refreshInterval(5), 15)
    assert.equal(S.refreshInterval(99999), 3600)
    assert.equal(S.refreshInterval(100), 90)
})
