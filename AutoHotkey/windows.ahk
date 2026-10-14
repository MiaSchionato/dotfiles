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
; a drag starts we already know which windows are floating.
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


; Win + left drag. A floating window follows the cursor. A tiled one is NOT
; moved (komorebi fights back and it flickers): it stays in the tiling and swaps
; places with the tile under the cursor, as in Hyprland.
DragOrToggle() {
    global lastClick, winHeld, statePid, stateAt
    winHeld := true              ; F20 comes with Win held
    CoordMode "Mouse", "Screen"
    SetWinDelay -1
    MouseGetPos &mx0, &my0, &hwnd
    if !CanMove(hwnd)
        return

    if (!statePid || A_TickCount - stateAt > 10000) {   ; Win went down long ago
        statePid := PrefetchState()
        stateAt := A_TickCount
    }
    ; Focus and raise the window at once: a floating one is moved with NOACTIVATE,
    ; so without this a window that was behind stays behind.
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
            tiled := !IsFloating(hwnd, statePid)    ; waits only if still being read
            statePid := 0
            if tiled {
                SwapWhileDragging(hwnd, TiledHwnds())
                break
            }
            RestoreIfMaximized(hwnd, mx0, my0)
            WinGetPos &wx, &wy, , , "ahk_id " hwnd
            dx := wx - mx0
            dy := wy - my0
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
        statePid := 0
        Run KOMOREBIC " toggle-float", , "Hide"
    } else {
        lastClick := A_TickCount
    }
}


; The drag of a tiled window. It is never moved by hand. When the cursor enters
; ANOTHER tiled window, one `komorebic move <direction>` (towards that window)
; puts the dragged one there, exactly like Win+Shift+H/J/K/L. A target that is
; not a neighbour (diagonal in a BSP layout) takes several moves, so the loop
; goes on after a move, but only while the move brought the dragged window
; closer to the cursor, and at most 4 times in a row: a move that lands
; somewhere else (another monitor...) stops the chain instead of dancing. The
; chain counts start over when the cursor is inside the dragged window again.
; The cursor must not be warped to the window by komorebi meanwhile, so
; mouse_follows_focus is off for the length of the drag.
SwapWhileDragging(hwnd, tiled) {
    global winHeld, lHeld
    Run KOMOREBIC " mouse-follows-focus disable", , "Hide"
    try {
        armed := true
        steps := 0
        began := A_TickCount
        while winHeld && lHeld {
            MouseGetPos &mx, &my, &under
            WinGetPos &rx, &ry, &rw, &rh, "ahk_id " hwnd
            if (mx >= rx && mx < rx + rw && my >= ry && my < ry + rh) {
                armed := true
                steps := 0
            } else if (armed && under != hwnd && tiled.Has(under + 0)) {
                before := RectDistance(mx, my, rx, ry, rw, rh)
                WinGetPos &tx, &ty, &tw, &th, "ahk_id " under
                vx := (tx + tw // 2) - (rx + rw // 2)
                vy := (ty + th // 2) - (ry + rh // 2)
                if (Abs(vx) >= Abs(vy))
                    dir := (vx < 0) ? "left" : "right"
                else
                    dir := (vy < 0) ? "up" : "down"
                Run KOMOREBIC " move " dir, , "Hide"
                t := A_TickCount
                while (A_TickCount - t < 250) {             ; until the layout changes
                    Sleep 10
                    WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
                    if (x != rx || y != ry || w != rw || h != rh)
                        break
                }
                Sleep 60
                WinGetPos &rx, &ry, &rw, &rh, "ahk_id " hwnd
                MouseGetPos &mx, &my
                steps += 1
                armed := (steps < 4 && RectDistance(mx, my, rx, ry, rw, rh) < before)
            }
            if (A_TickCount - began > 30000)
                break                   ; safety brake
            Sleep 5
        }
    }
    Run KOMOREBIC " mouse-follows-focus enable", , "Hide"
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
    FloatIfTiled(hwnd, PrefetchState())
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

; Distance from a point to a rectangle (0 when inside).
RectDistance(px, py, rx, ry, rw, rh) {
    ox := (px < rx) ? rx - px : (px >= rx + rw ? px - (rx + rw) + 1 : 0)
    oy := (py < ry) ? ry - py : (py >= ry + rh ? py - (ry + rh) + 1 : 0)
    return Sqrt(ox * ox + oy * oy)
}

; The windows komorebi tiles, from the state file IsFloating has just read:
; every hwnd in it minus the ones in floating_windows. Map of hwnd -> true.
TiledHwnds() {
    state := ""
    try state := FileRead(A_Temp "\komorebi-state.json")
    tiled := Map()
    pos := 1
    while RegExMatch(state, '"hwnd":\s*(\d+)', &m, pos) {
        tiled[Integer(m[1])] := true
        pos := m.Pos + m.Len
    }
    pos := 1
    while RegExMatch(state, 's)"floating_windows":\s*\{\s*"elements":\s*\[(.*?)\]\s*,\s*"focused"', &m, pos) {
        inner := m[1]
        ipos := 1
        while RegExMatch(inner, '"hwnd":\s*(\d+)', &w, ipos) {
            tiled.Delete(Integer(w[1]))
            ipos := w.Pos + w.Len
        }
        pos := m.Pos + m.Len
    }
    return tiled
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
