#Requires AutoHotkey v2.0

; =============================================================
;  windows - Win + mouse to move and resize windows, with komorebi
;
;    Win + left button         drag: move the window (a tiled window
;                              becomes floating when the drag starts)
;    Win + right button        drag: resize from the nearest corner
;                              (also floats a tiled window)
;    Win + double left click   toggle tiled / floating
;
;  Based on Videos/AutoHotkey/janelas.ahk (2026-09-01), moved here and
;  taken to komorebi's side: moving a tiled window with SetWindowPos
;  behind komorebi's back made it fight back (see READTHIS.md), so a tiled
;  window is floated first, once, with `komorebic toggle-float`.
;
;  With a pen, only the title bar works: inside the client area the apps
;  with Windows Ink support (Discord, Zen, ...) take the pen through the
;  pointer API, and Windows never generates the mouse message AHK listens
;  to. Nothing to do about it without reading the digitizer in raw input,
;  or turning Ink off.
; =============================================================

#HotIf                      ; do not inherit a context from another file
#SingleInstance Force

DOUBLE_CLICK_MS := 350      ; two clicks closer than this are a double click
KOMOREBIC := "komorebic-no-console.exe"
lastClick := 0

; kanata swallows the Win key (tap = launcher, hold = command layer), so AHK
; never sees it. While Win is held kanata holds F24 (virtual key vk-win in
; the kanata config), and F24 stands for Win here. GetKeyState("F24") always
; answers 0 for a key kanata injects, so winHeld tracks it instead.
winHeld := false
lHeld := false
rHeld := false
~F24 up:: global winHeld := false

; Win + left click arrives from kanata as F20 (vk-lclick in the kanata config):
; one event, in order, and the click never reaches the program. kanata releases
; that key on its own if Windows does not see it pressed (a plain `F20::` hotkey
; swallows it: "Unexpected keycode is pressed in kanata but not in Windows"), so
; the hotkeys keep the ~ prefix: F20 stays down exactly as long as the button,
; and `F20 up` ends the drag. GetKeyState("LButton", "P") cannot be used: whether
; AHK sees the swallowed click depends on the order of the mouse hooks.
; Win + right click is F21 the same way.
~F20:: {
    global lHeld := true
    DragOrToggle()
}
~F20 up:: {
    global lHeld := false
}
~F21:: {
    global rHeld := true
    ResizeWindow()
}
~F21 up:: {
    global rHeld := false
}

; Win+Y: kanata taps F22. Scratchpad workspace (Omarchy's scratchpad on
; komorebi): go to the "Scratchpad" workspace, or back to the previous one
; when already there. Win+Shift+Y (sending the window) is kanata's own.
; Win+Q (force quit) is kanata's own now: nu -c in the kanata configs.
F22:: ToggleScratchpad()


DragOrToggle() {
    global lastClick, winHeld
    winHeld := true              ; F20 comes with Win held
    CoordMode "Mouse", "Screen"
    SetWinDelay -1
    MouseGetPos &mx0, &my0, &hwnd
    if !CanMove(hwnd)
        return

    ; Focus and raise the window at once: the drag moves it with NOACTIVATE, so
    ; without this a window that was behind stays behind. komorebi follows the
    ; focus change by itself.
    ; Is the window tiled? Asked in the background while the button is still
    ; waiting for its first pixel, so a floating window finds the answer ready.
    ; A window already in focus is asked about at once; one that has to be
    ; focused first waits 25 ms for komorebi to hear about the focus change.
    askAfter := WinActive("ahk_id " hwnd) ? 0 : 25
    try WinActivate "ahk_id " hwnd
    DllCall("winmm\timeBeginPeriod", "UInt", 1)    ; 1 ms Sleep, not 15
    kindQuery := ""
    pressedAt := A_TickCount
    started := false
    lastX := lastY := ""
    began := A_TickCount
    while winHeld && lHeld {
        MouseGetPos &mx, &my
        if !started {
            if (kindQuery = "" && A_TickCount - pressedAt >= askAfter)
                kindQuery := StartKindQuery()
            if (mx = mx0 && my = my0) {
                Sleep 1
                continue
            }
            started := true
            ; The first pixel: let komorebi let go of the window (once, before
            ; any move, so the two never fight over it), then grab it at the
            ; same relative point of whatever size it ends up with.
            WinGetPos &wx, &wy, &ww, &wh, "ahk_id " hwnd
            fx := ww ? (mx0 - wx) / ww : 0.5
            fy := wh ? (my0 - wy) / wh : 0.5
            EnsureFloating(hwnd, kindQuery ? ReadKind(kindQuery) : QueryKind())
            if (WinGetMinMax("ahk_id " hwnd) = 1) {     ; Adobe windows: maximized
                WinRestore "ahk_id " hwnd
                Sleep 60
            }
            MouseGetPos &mx, &my                        ; it kept moving meanwhile
            WinGetPos , , &nw, &nh, "ahk_id " hwnd
            dx := -Round(fx * nw)
            dy := -Round(fy * nh)
        }
        if (mx != lastX || my != lastY) {
            if !MoveAsync(hwnd, mx + dx, my + dy)
                break                   ; the window closed mid-drag
            lastX := mx, lastY := my
        }
        if (A_TickCount - began > 30000)
            break                       ; safety brake
        Sleep 1
    }
    DllCall("winmm\timeEndPeriod", "UInt", 1)

    if started
        return
    ; Pressed and released without moving: a click. Two close ones toggle.
    if (A_TickCount - lastClick < DOUBLE_CLICK_MS) {
        lastClick := 0
        Run KOMOREBIC " toggle-float", , "Hide"
    } else {
        lastClick := A_TickCount
    }
}


ResizeWindow() {
    global winHeld
    winHeld := true
    CoordMode "Mouse", "Screen"
    SetWinDelay -1
    MouseGetPos &mx, &my, &hwnd
    if !CanMove(hwnd)
        return
    if (WinGetMinMax("ahk_id " hwnd) = 1)
        return                          ; maximized: nothing to resize

    try WinActivate "ahk_id " hwnd      ; focus and raise it, as the move does
    FocusWindow(hwnd)
    EnsureFloating(hwnd, QueryKind())
    WinGetPos &wx, &wy, &ww, &wh, "ahk_id " hwnd
    left := (mx < wx + ww // 2)         ; the quadrant the drag began in
    top := (my < wy + wh // 2)

    while rHeld {
        MouseGetPos &nx, &ny
        dx := nx - mx                   ; total delta since the start, not
        dy := ny - my                   ; incremental: no error piles up
        x := wx, y := wy, w := ww, h := wh
        if left
            x += dx, w -= dx
        else
            w += dx
        if top
            y += dy, h -= dy
        else
            h += dy
        if (w >= 150 && h >= 100) {     ; do not let the window collapse
            try WinMove x, y, w, h, "ahk_id " hwnd
            catch
                break
        }
        Sleep 10
    }
}


; Make sure komorebi does not tile the window, without it noticing a fight:
; `komorebic toggle-float` acts on the focused window, so the window has to be
; focused first. kind is komorebi's view of the focused window (QueryKind);
; then wait for komorebi to lay the window out as a floating one.
EnsureFloating(hwnd, kind) {
    if !(kind = "Single" || kind = "Stack" || kind = "Monocle")
        return                          ; Floating (or no answer): leave it alone
    FocusWindow(hwnd)
    WinGetPos &x0, &y0, &w0, &h0, "ahk_id " hwnd
    RunWait KOMOREBIC " toggle-float", , "Hide"
    t := A_TickCount
    while (A_TickCount - t < 150) {
        WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
        if (x != x0 || y != y0 || w != w0 || h != h0) {
            Sleep 20                    ; let it settle
            break
        }
        Sleep 5
    }
}

FocusWindow(hwnd) {
    if !WinActive("ahk_id " hwnd) {
        try WinActivate "ahk_id " hwnd
        WinWaitActive "ahk_id " hwnd, , 0.3
    }
    Sleep 15                            ; komorebi hears about the focus change
}

; komorebi's view of the focused window: Single / Stack / Monocle when tiled,
; Floating when not. StartKindQuery does not wait; ReadKind waits for the answer.
StartKindQuery() {
    try return ComObject("WScript.Shell").Exec(KOMOREBIC " query focused-container-kind")
    return ""
}

ReadKind(exec) {
    try return Trim(exec.StdOut.ReadAll(), " `t`r`n")
    return ""
}

QueryKind() {
    exec := StartKindQuery()
    return exec ? ReadKind(exec) : ""
}


; SetWindowPos with SWP_ASYNCWINDOWPOS does not wait for the window's
; thread. WinMove waits, and on heavy apps (Electron) that makes the drag
; stutter. NOSIZE|NOZORDER|NOACTIVATE|ASYNC = 0x4015.
MoveAsync(hwnd, x, y) {
    return DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0,
                   "Int", x, "Int", y, "Int", 0, "Int", 0,
                   "UInt", 0x4015)
}

ButtonDown(b) {
    return GetKeyState(b, "P") || GetKeyState(b)
}

; Not the taskbar, the desktop, or a window that does not exist.
CanMove(hwnd) {
    static skip := ["Shell_TrayWnd", "Shell_SecondaryTrayWnd",
                    "Progman", "WorkerW", "NotifyIconOverflowWindow"]
    if !hwnd
        return false
    cls := ""
    try cls := WinGetClass("ahk_id " hwnd)
    if (cls = "")
        return false
    for c in skip
        if (cls = c)
            return false
    return true
}


ToggleScratchpad() {
    tmp := A_Temp "\komorebi-workspace.txt"
    try FileDelete tmp
    RunWait A_ComSpec ' /c ' KOMOREBIC ' query focused-workspace-name > "' tmp '"', , "Hide"
    name := ""
    try name := Trim(FileRead(tmp), " `t`r`n")
    if (name = "Scratchpad")
        Run KOMOREBIC " focus-last-workspace", , "Hide"
    else
        Run KOMOREBIC " focus-named-workspace Scratchpad", , "Hide"
}
