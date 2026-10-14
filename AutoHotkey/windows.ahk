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
; answers 0 for a key kanata injects, so winHeld tracks it instead. When Win
; goes down komorebi's state is read in the background (statePid): by the time
; the drag starts we already know which windows are floating.
winHeld := false
lHeld := false
rHeld := false
statePid := 0
stateAt := 0
~F24:: {
    global winHeld, statePid, stateAt
    if winHeld
        return                          ; auto-repeat
    winHeld := true
    statePid := PrefetchState()
    stateAt := A_TickCount
}
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
    global lastClick, winHeld, statePid
    winHeld := true              ; F20 comes with Win held
    CoordMode "Mouse", "Screen"
    SetWinDelay -1
    MouseGetPos &mx0, &my0, &hwnd
    if !CanMove(hwnd)
        return

    ; Focus and raise the window at once: the drag moves it with NOACTIVATE, so
    ; without this a window that was behind stays behind. komorebi follows the
    ; focus change by itself.
    try WinActivate "ahk_id " hwnd
    DllCall("winmm\timeBeginPeriod", "UInt", 1)    ; 1 ms Sleep, not 15
    started := false
    lastX := lastY := ""
    began := A_TickCount
    while winHeld && lHeld {
        MouseGetPos &mx, &my
        if !started {
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
            EnsureFloating(hwnd)
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
        statePid := 0                   ; the cached state is stale now
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
    EnsureFloating(hwnd)
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
; focused first. Whether it is tiled comes from the state read when Win went
; down, or, if that is not ready, from asking komorebi about the focused window
; (a few ms). Then wait for komorebi to lay the window out as a floating one.
EnsureFloating(hwnd) {
    global statePid
    floating := KnownFloating(hwnd)
    if (floating = -1) {
        FocusWindow(hwnd)
        kind := QueryKind()
        floating := !(kind = "Single" || kind = "Stack" || kind = "Monocle")
    }
    if floating
        return
    FocusWindow(hwnd)
    WinGetPos &x0, &y0, &w0, &h0, "ahk_id " hwnd
    RunWait KOMOREBIC " toggle-float", , "Hide"
    statePid := 0                       ; the cached state is stale now
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
; Floating when not.
QueryKind() {
    try {
        exec := ComObject("WScript.Shell").Exec(KOMOREBIC " query focused-container-kind")
        return Trim(exec.StdOut.ReadAll(), " `t`r`n")
    }
    return ""
}

; 1 / 0 from the state read when Win went down, -1 when there is none.
KnownFloating(hwnd) {
    global statePid, stateAt
    if (!statePid || A_TickCount - stateAt > 10000)
        return -1
    if ProcessExist(statePid)
        ProcessWaitClose statePid, 0.15
    if ProcessExist(statePid)
        return -1
    return IsFloating(hwnd, statePid) ? 1 : 0
}

; Starts `komorebic state` in the background, writing to a temp file; returns the
; PID to wait on (IsFloating does).
PrefetchState() {
    tmp := A_Temp "\komorebi-state.json"
    try FileDelete tmp
    Run A_ComSpec ' /c ' KOMOREBIC ' state > "' tmp '"', , "Hide", &pid
    return pid
}

; True when komorebi does not tile the window: it is in a workspace's
; floating_windows, or komorebi does not manage it at all.
IsFloating(hwnd, statePid := 0) {
    tmp := A_Temp "\komorebi-state.json"
    if !statePid
        statePid := PrefetchState()
    ProcessWaitClose statePid, 2
    state := ""
    try state := FileRead(tmp)
    if (state = "")
        return true                     ; no answer: do not touch komorebi
    pos := 1
    while RegExMatch(state, 's)"floating_windows":\s*\{\s*"elements":\s*\[(.*?)\]\s*,\s*"focused"', &m, pos) {
        if RegExMatch(m[1], '"hwnd":\s*' hwnd '\b')
            return true
        pos := m.Pos + m.Len
    }
    ; Tiled windows are in a container's windows; no match anywhere: unmanaged
    return !RegExMatch(state, '"hwnd":\s*' hwnd '\b')
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
