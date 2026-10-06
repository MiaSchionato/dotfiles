#Requires AutoHotkey v2.0

; =============================================================
;  pan - CapsLock + click = right click
;        (drag-to-pan is fully disabled, see below)
;
;  History, so it isn't repeated:
;
;  The pan used to live on Shift and was moved off it because it got
;  in the way in DaVinci.
;
;  On 2026-09-05, when moving it to CapsLock, the button check the
;  Shift version had was lost, and the loop ran for as long as the KEY
;  was held. One click with CapsLock down (also the hjkl layer) turned
;  every mouse movement into scrolling for up to 30 s -- with Ctrl
;  held, each of those events is a zoom step. Resolve hung that
;  afternoon. It was never proven to be this, but the defect was real.
;
;  That's where the three guards below came from: button check,
;  capped rate, and a ceiling on the accumulator.
; =============================================================

#HotIf GetKeyState("CapsLock", "P")
LButton:: {
    ; CapsLock rather than Shift: in graph editors Shift+drag
    ; constrains the axis, and this hotkey used to swallow that
    ; gesture. Handing the drag back to the app didn't work -- the
    ; button down would land 8 px off, losing the keyframe you meant
    ; to grab. No app uses CapsLock, so it collides with nothing.
    Click "Right"
}
#HotIf

; ALL DISABLED 2026-09-05 21:18. Three Resolve hangs that afternoon,
; two of them with drag-to-wheel code active. Not proven to be the
; cause, and the 20:52 hang has another explanation (a hung AHK
; process blocks the whole input chain), but while in doubt no
; synthetic input gets added.
;
; To re-enable, uncomment. Do NOT re-enable all three at once: one at
; a time, with days of use in between, or nothing is learned.
; ^LButton::Pan("Ctrl", true)
; !LButton::Pan("Alt", true)
; #HotIf GetKeyState("CapsLock", "P")
; LButton::Pan("CapsLock", false)
; #HotIf


; CapsLock rather than Ctrl: Ctrl+drag already means something almost
; everywhere (copy in Explorer, add to selection in a timeline, open
; in a new tab). No app uses CapsLock. To swap, change the key in the
; lines above.
; passClick: if you didn't drag, the click is re-sent to the app.
; That's what keeps Ctrl+click and Alt+click working, since they mean
; something almost everywhere -- only the DRAG is taken over.
Pan(key, passClick) {
    DRAG_THRESHOLD := 8               ; px before it counts as a drag
    WHEEL_STEP     := 35              ; px of drag per wheel "click"
    MIN_INTERVAL   := 25              ; min ms between events -> cap of 40/s
    ACC_CAP        := WHEEL_STEP * 3  ; the accumulator never goes past this
    TIMEOUT_MS     := 15000           ; ms, safety brake

    CoordMode "Mouse", "Screen"
    ; Mask key: with Alt held and the click suppressed, releasing Alt
    ; would open the app's menu bar.
    Send "{Blind}{vkE8}"
    MouseGetPos &x0, &y0
    prevX := x0, prevY := y0
    accX := 0, accY := 0
    dragged := false
    sawButton := false
    lastSendTick := 0
    startTick := A_TickCount

    while GetKeyState(key, "P") {
        ; Guard 1: the button rules. Once seen, releasing it ends the
        ; pan -- without this, holding CapsLock for hjkl after a click
        ; turned every movement into scrolling.
        if IsButtonDown("LButton")
            sawButton := true
        else if sawButton
            break

        MouseGetPos &x, &y
        if (!dragged && (Abs(x - x0) > DRAG_THRESHOLD || Abs(y - y0) > DRAG_THRESHOLD))
            dragged := true
        ; Guard 3: ceiling on the accumulator. A violent drag doesn't
        ; build a queue that keeps scrolling after you stop.
        accX := ClampValue(accX + (x - prevX), ACC_CAP)
        accY := ClampValue(accY + (y - prevY), ACC_CAP)
        prevX := x, prevY := y

        ; Guard 2: rate. At most one event per axis every MIN_INTERVAL
        ; ms, instead of as many as fit in each loop pass.
        now := A_TickCount
        if (dragged && now - lastSendTick >= MIN_INTERVAL) {
            sent := false
            if (Abs(accY) >= WHEEL_STEP) {
                Send (accY > 0) ? "{WheelDown}" : "{WheelUp}"
                accY -= (accY > 0) ? WHEEL_STEP : -WHEEL_STEP
                sent := true
            }
            if (Abs(accX) >= WHEEL_STEP) {
                Send (accX > 0) ? "{WheelRight}" : "{WheelLeft}"
                accX -= (accX > 0) ? WHEEL_STEP : -WHEEL_STEP
                sent := true
            }
            if sent
                lastSendTick := now
        }

        if (A_TickCount - startTick > TIMEOUT_MS)
            break
        Sleep 10
    }

    if (!dragged && passClick)
        Send "{Blind}{Click}"  ; Blind keeps Ctrl/Alt held
}

ClampValue(v, cap) {
    return (v > cap) ? cap : (v < -cap) ? -cap : v
}
