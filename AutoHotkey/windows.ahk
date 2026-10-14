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
DRAG_THRESHOLD := 2         ; px before a press counts as a drag
KOMOREBIC := "komorebic-no-console.exe"
lastClick := 0

; kanata swallows the Win key (tap = launcher, hold = command layer), so AHK
; never sees it. While Win is held kanata holds F24 (virtual key vk-win in
; the kanata configs), and F24 stands for Win here. The combos F24 & LButton /
; F24 & RButton are matched inside AHK's own hook, so the click never reaches
; the program under the cursor (a #HotIf variable set by another thread raced
; with the click and let it through). GetKeyState("F24") always answers 0 for
; a key kanata injects, so the drag loops follow winHeld instead, set by the
; combos and cleared when F24 goes up.
winHeld := false
~F24 up:: global winHeld := false

; Win + left click arrives from kanata as F20 (vk-lclick in the kanata config):
; one event, in order, and the click never reaches the program. kanata releases
; that key after ~20 ms whatever the button does, so F20 is only the trigger;
; the drag follows the physical button (GetKeyState "P" sees it even though
; kanata swallows the click). Win + right click is still the F24 combo.
F20:: DragOrToggle()
F24 & RButton:: ResizeWindow()

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

    ; komorebi's state is read while the press is still waiting for the first
    ; pixel of movement, so the drag does not wait for it afterwards.
    statePid := PrefetchState()
    started := false
    began := A_TickCount
    while winHeld && GetKeyState("LButton", "P") {
        MouseGetPos &mx, &my
        if !started {
            if (Abs(mx - mx0) < DRAG_THRESHOLD && Abs(my - my0) < DRAG_THRESHOLD) {
                Sleep 10
                continue
            }
            started := true
            FloatIfTiled(hwnd, statePid)
            RestoreIfMaximized(hwnd, mx0, my0)
            WinGetPos &wx, &wy, , , "ahk_id " hwnd
            dx := wx - mx0
            dy := wy - my0
        }
        if !MoveAsync(hwnd, mx + dx, my + dy)
            break                       ; the window closed mid-drag
        if (A_TickCount - began > 30000)
            break                       ; safety brake
        Sleep 10
    }

    if started
        return
    ; Pressed and released without moving: a click. Two close ones toggle.
    if (A_TickCount - lastClick < DOUBLE_CLICK_MS) {
        lastClick := 0
        try WinActivate "ahk_id " hwnd
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

    FloatIfTiled(hwnd, PrefetchState())
    WinGetPos &wx, &wy, &ww, &wh, "ahk_id " hwnd
    left := (mx < wx + ww // 2)         ; the quadrant the drag began in
    top := (my < wy + wh // 2)

    while GetKeyState("RButton", "P") {
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


; A maximized window is restored with the cursor on the SAME relative
; point of it, or it would jump from under the pointer (the Adobe windows
; are almost always maximized).
RestoreIfMaximized(hwnd, mx, my) {
    if (WinGetMinMax("ahk_id " hwnd) != 1)
        return
    WinGetPos &ax, &ay, &aw, &ah, "ahk_id " hwnd
    fx := aw ? (mx - ax) / aw : 0.5
    fy := ah ? (my - ay) / ah : 0.5
    WinRestore "ahk_id " hwnd
    Sleep 60
    WinGetPos , , &nw, &nh, "ahk_id " hwnd
    try WinMove mx - Round(fx * nw), my - Round(fy * nh), , , "ahk_id " hwnd
}


; Float the window if komorebi tiles it: `komorebic toggle-float` acts on
; the focused window, so focus it first. Asking komorebi's state once per
; drag is a process spawn, fine for a discrete step (not per frame).
FloatIfTiled(hwnd, statePid := 0) {
    if IsFloating(hwnd, statePid)
        return
    try WinActivate "ahk_id " hwnd
    RunWait KOMOREBIC " toggle-float", , "Hide"
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
