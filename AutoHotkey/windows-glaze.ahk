#Requires AutoHotkey v2.0

; =============================================================
;  windows-glaze - the same Win + mouse gestures as windows.ahk, on GlazeWM
;  (pilot, 2026-10-14; windows.ahk and komorebi are untouched).
;
;    Win + left button         drag: move the window (a tiled window is
;                              floated where it is when the drag starts)
;    Win + right button        drag: resize from the nearest corner
;    Win + double left click   toggle tiled / floating
;
;  kanata sends the gestures as keys (see windows.ahk): F24 = Win held,
;  F20 = left click (held while the button is), F21 = right click.
;  GlazeWM's CLI acts on any window by id (`command --id`), so, unlike
;  komorebic, the window does not have to be focused first.
; =============================================================

#HotIf
#SingleInstance Force

DOUBLE_CLICK_MS := 350      ; two clicks closer than this are a double click
GLAZE := '"C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"'
lastClick := 0
winHeld := false
lHeld := false
rHeld := false
queryPid := 0
queryAt := 0

~F24:: {
    global winHeld, queryPid, queryAt
    if winHeld
        return                          ; auto-repeat
    winHeld := true
    queryPid := PrefetchWindows()       ; know the floating windows beforehand
    queryAt := A_TickCount
}
~F24 up:: global winHeld := false

~F20:: {
    global lHeld := true
    DragOrToggle()
}
~F20 up:: global lHeld := false
~F21:: {
    global rHeld := true
    ResizeWindow()
}
~F21 up:: global rHeld := false


DragOrToggle() {
    global lastClick, winHeld, queryPid, queryAt
    winHeld := true
    CoordMode "Mouse", "Screen"
    SetWinDelay -1
    MouseGetPos &mx0, &my0, &hwnd
    if !CanMove(hwnd)
        return
    if (!queryPid || A_TickCount - queryAt > 10000) {
        queryPid := PrefetchWindows()
        queryAt := A_TickCount
    }
    try WinActivate "ahk_id " hwnd          ; focus and raise it
    DllCall("winmm\timeBeginPeriod", "UInt", 1)
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
            FloatIfTiled(hwnd, queryPid)
            queryPid := 0
            RestoreIfMaximized(hwnd, mx0, my0)
            WinGetPos &wx, &wy, , , "ahk_id " hwnd
            dx := wx - mx0
            dy := wy - my0
        }
        if (mx != lastX || my != lastY) {
            if !MoveAsync(hwnd, mx + dx, my + dy)
                break                       ; the window closed mid-drag
            lastX := mx, lastY := my
        }
        if (A_TickCount - began > 30000)
            break                           ; safety brake
        Sleep 1
    }
    DllCall("winmm\timeEndPeriod", "UInt", 1)

    if started
        return
    ; Pressed and released without moving: a click. Two close ones toggle.
    if (A_TickCount - lastClick < DOUBLE_CLICK_MS) {
        lastClick := 0
        queryPid := 0
        id := GlazeInfo(hwnd, &state, PrefetchWindows())
        if id
            Run GLAZE ' command --id ' id ' toggle-floating', , "Hide"
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
        return                              ; maximized: nothing to resize

    try WinActivate "ahk_id " hwnd
    FloatIfTiled(hwnd, PrefetchWindows())
    WinGetPos &wx, &wy, &ww, &wh, "ahk_id " hwnd
    left := (mx < wx + ww // 2)             ; the quadrant the drag began in
    top := (my < wy + wh // 2)

    while rHeld {
        MouseGetPos &nx, &ny
        dx := nx - mx                       ; total delta since the start, not
        dy := ny - my                       ; incremental: no error piles up
        x := wx, y := wy, w := ww, h := wh
        if left
            x += dx, w -= dx
        else
            w += dx
        if top
            y += dy, h -= dy
        else
            h += dy
        if (w >= 150 && h >= 100) {         ; do not let the window collapse
            try WinMove x, y, w, h, "ahk_id " hwnd
            catch
                break
        }
        Sleep 10
    }
}


; A maximized window is restored with the cursor on the SAME relative
; point of it, or it would jump from under the pointer.
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


; Float a tiled window where it is (same position and size, not centered), so it
; does not jump. GlazeWM takes the window by id: no focus needed, no race.
FloatIfTiled(hwnd, queryPid := 0) {
    id := GlazeInfo(hwnd, &state, queryPid)
    if (!id || state != "tiling")
        return
    WinGetPos &x, &y, &w, &h, "ahk_id " hwnd
    RunWait GLAZE ' command --id ' id ' set-floating --centered=false --x-pos ' x
        . ' --y-pos ' y ' --width ' w ' --height ' h, , "Hide"
}

; Starts `glazewm query windows` in the background, into a temp file; returns
; the PID to wait on.
PrefetchWindows() {
    tmp := A_Temp "\glazewm-windows.json"
    try FileDelete tmp
    Run A_ComSpec ' /c ' GLAZE ' query windows > "' tmp '"', , "Hide", &pid
    return pid
}

; GlazeWM's container id of a window (its handle is the hwnd) and its state
; type (tiling / floating / minimized / fullscreen). "" when GlazeWM does not
; manage it. Waits for the query only if it has not finished.
GlazeInfo(hwnd, &state, queryPid := 0) {
    tmp := A_Temp "\glazewm-windows.json"
    if !queryPid
        queryPid := PrefetchWindows()
    ProcessWaitClose queryPid, 2
    json := ""
    try json := FileRead(tmp)
    state := ""
    for chunk in StrSplit(json, '{"type":"window"') {
        if !RegExMatch(chunk, '"handle":' hwnd '[,}]')
            continue
        if RegExMatch(chunk, '"id":"([^"]+)"', &mi) && RegExMatch(chunk, '"state":\{"type":"(\w+)"', &ms) {
            state := ms[1]
            return mi[1]
        }
    }
    return ""
}


; SetWindowPos with SWP_ASYNCWINDOWPOS does not wait for the window's
; thread. NOSIZE|NOZORDER|NOACTIVATE|ASYNC = 0x4015.
MoveAsync(hwnd, x, y) {
    return DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0,
                   "Int", x, "Int", y, "Int", 0, "Int", 0,
                   "UInt", 0x4015)
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
