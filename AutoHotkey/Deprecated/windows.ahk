#Requires AutoHotkey v2.0

; =============================================================
;  windows - Win + mouse to move, resize and maximize windows
;
;    Win + left drag     ->  moves the window
;    Win + double click  ->  maximizes / restores
;    Win + right drag    ->  resizes from the nearest corner
;
;  With the pen it only works on the title bar: inside the client
;  area, apps with Windows Ink support (Discord, Zen, ...) consume the
;  pen through the pointer API, and Windows never generates the mouse
;  message AHK listens for. No way around it short of reading the
;  digitizer via raw input, or turning Ink off.
; =============================================================

#HotIf  ; make sure no context is inherited from another file

#LButton::OnWinClick()
#RButton::DragResizeWindow()




; Win + double click = toggle maximize/restore, like double-clicking
; the title bar. A_PriorHotkey can't be used: the Win mask (OnWinDown
; in shortcuts.ahk) fires on every auto-repeat while Win is held, so
; it is always the "prior hotkey". The previous click's time and
; position are kept here instead.
OnWinClick() {
    static lastTick := 0, lastX := 0, lastY := 0
    CoordMode "Mouse", "Screen"
    MouseGetPos &x, &y
    isDouble := (A_TickCount - lastTick < DllCall("GetDoubleClickTime"))
             && Abs(x - lastX) <= 8 && Abs(y - lastY) <= 8
    if isDouble {
        lastTick := 0  ; a third click doesn't count as another double
        ToggleMaximize()
        return
    }
    lastTick := A_TickCount, lastX := x, lastY := y
    DragMoveWindow()
}

; Through komorebic, not WinMaximize: komorebi does not notice
; external window moves, so a native maximize on a tiled window
; desyncs its layout model silently.
ToggleMaximize() {
    Komorebi("toggle-maximize")
}


DragMoveWindow() {
    DRAG_THRESHOLD := 8  ; px before it counts as a drag
    CoordMode "Mouse", "Screen"
    SetWinDelay -1
    Send "{Blind}{vkE8}"  ; mask key: keeps the Start menu from opening
    MouseGetPos &x0, &y0, &hwnd
    if !IsMovable(hwnd)
        return

    dragging := false
    dx := 0, dy := 0
    startTick := A_TickCount
    sawButton := false
    ; The drag lasts while Win is held; once the button has been seen
    ; (mouse), releasing it ends the drag. The pen keeps no
    ; button state, so the button alone can't be relied on.
    while (GetKeyState("LWin", "P") || GetKeyState("RWin", "P")) {
        if (A_TickCount - startTick > 30000)
            break  ; safety brake
        if IsButtonDown("LButton")
            sawButton := true
        else if sawButton
            break  ; mouse: button released
        MouseGetPos &mx, &my

        ; Nothing moves until the threshold is passed: a still click does
        ; nothing. The click used to restore a maximized window right
        ; away, which made double-clicking to restore it impossible.
        if !dragging {
            if (Abs(mx - x0) <= DRAG_THRESHOLD && Abs(my - y0) <= DRAG_THRESHOLD) {
                Sleep 10
                continue
            }
            dragging := true
            ; Maximized: restore it keeping the grabbed point at the SAME
            ; relative spot of the window, otherwise it jumps under the
            ; pointer (which is what happened with Adobe windows).
            if (WinGetMinMax("ahk_id " hwnd) = 1) {
                WinGetPos &ax, &ay, &aw, &ah, "ahk_id " hwnd
                fx := aw ? (x0 - ax) / aw : 0.5
                fy := ah ? (y0 - ay) / ah : 0.5
                WinRestore "ahk_id " hwnd
                Sleep 60
                WinGetPos , , &nw, &nh, "ahk_id " hwnd
                try WinMove x0 - Round(fx * nw), y0 - Round(fy * nh), , , "ahk_id " hwnd
            }
            WinGetPos &wx, &wy, , , "ahk_id " hwnd
            dx := wx - x0
            dy := wy - y0
        }

        if !MoveAsync(hwnd, mx + dx, my + dy)
            break  ; window closed mid-drag
        Sleep 10
    }

    ; komorebi ignores external moves: it neither snaps the window back
    ; nor re-tiles around it, so its model and the screen drift apart
    ; and stay that way. retile reconciles them. On a floating window
    ; (Adobe, Explorer) this is a no-op and the drag just works; on a
    ; tiled one the window returns, which is the honest outcome -- use
    ; Win+Shift+hjkl to move those.
    Komorebi("retile")
}


DragResizeWindow() {
    CoordMode "Mouse", "Screen"
    SetWinDelay -1
    Send "{Blind}{vkE8}"  ; mask key: keeps the Start menu from opening
    MouseGetPos &mx, &my, &hwnd
    if !IsMovable(hwnd)
        return
    if (WinGetMinMax("ahk_id " hwnd) = 1)
        return  ; maximized: nothing to resize

    WinGetPos &wx, &wy, &ww, &wh, "ahk_id " hwnd
    grabLeft := (mx < wx + ww // 2)  ; quadrant where the drag started
    grabTop  := (my < wy + wh // 2)

    while GetKeyState("RButton", "P") {
        MouseGetPos &nx, &ny
        dx := nx - mx  ; total delta since the start,
        dy := ny - my  ; not incremental: no accumulated error
        x := wx, y := wy, w := ww, h := wh

        if grabLeft
            x += dx, w -= dx
        else
            w += dx
        if grabTop
            y += dy, h -= dy
        else
            h += dy

        if (w >= 150 && h >= 100) {  ; don't let the window collapse
            try WinMove x, y, w, h, "ahk_id " hwnd
            catch
                break
        }
        Sleep 10
    }

    ; komorebi ignores external moves: it neither snaps the window back
    ; nor re-tiles around it, so its model and the screen drift apart
    ; and stay that way. retile reconciles them. On a floating window
    ; (Adobe, Explorer) this is a no-op and the drag just works; on a
    ; tiled one the window returns, which is the honest outcome -- use
    ; Win+Shift+hjkl to move those.
    Komorebi("retile")
}


; SetWindowPos with SWP_ASYNCWINDOWPOS doesn't block waiting on the
; window's thread. WinMove does, and in heavy apps (Electron) that
; makes the drag stutter. NOSIZE|NOZORDER|NOACTIVATE|ASYNC = 0x4015.
MoveAsync(hwnd, x, y) {
    return DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0,
                   "Int", x, "Int", y, "Int", 0, "Int", 0,
                   "UInt", 0x4015)
}

IsButtonDown(b) {
    return GetKeyState(b, "P") || GetKeyState(b)
}

; Leave the taskbar, the desktop and nonexistent windows alone.
IsMovable(hwnd) {
    static ignoredClasses := ["Shell_TrayWnd", "Shell_SecondaryTrayWnd",
                              "Progman", "WorkerW", "NotifyIconOverflowWindow"]
    if !hwnd
        return false
    cls := ""
    try cls := WinGetClass("ahk_id " hwnd)
    if (cls = "")
        return false
    for c in ignoredClasses
        if (cls = c)
            return false
    return true
}
