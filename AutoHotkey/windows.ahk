#Requires AutoHotkey v2.0

; =============================================================
;  windows - Win + mouse to move and resize windows, with GlazeWM
;  (komorebi's version is in git history, before 2026-10-14).
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
DRAG_THRESHOLD := 3         ; px before a press counts as a drag: a hand always
                            ; moves the mouse a pixel or two inside a click
GLAZE := '"C:\Program Files\glzr.io\GlazeWM\cli\glazewm.exe"'
lastClick := 0
lastRClick := 0
winHeld := false
lHeld := false
rHeld := false
queryPid := 0
queryAt := 0

; Warm-up: the first call of the CLI is slow (cold start of the executable);
; do it now, not on the first Win + click.
Run GLAZE ' query app-metadata', , "Hide"

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

; Win + middle click closes the window under the cursor, politely (the same as
; its close button; an app may ask to save first).
~F19:: CloseWindowUnderCursor()

; A click on the bare desktop (an empty workspace has no window to click) focuses
; that monitor in GlazeWM, so the next app opens there: GlazeWM puts a new window
; on the workspace of the focused container, not where the pointer is.
~LButton:: FocusMonitorOfEmptyClick()


; Snap, like Windows': drag a window with Win + left button to a screen edge and
; a preview shows the side; letting go there puts it back in the tiling (left /
; right edge; the preview is only a hint, GlazeWM picks the tile) or fullscreen
; (top edge). Anywhere else it stays
; floating where it was dropped.
SNAP_EDGE := 40             ; px from the monitor edge that count as "at the edge"
SNAP_MIN_TRAVEL := 150      ; px the cursor must have moved: a press that starts
                            ; at an edge must not snap on its own
snapGui := ""
snapKind := ""

; The zone under the cursor: {kind: "left" | "right" | "top", x, y, w, h} (the
; preview rectangle, in the monitor's work area), or "" for none.
SnapZoneAt(mx, my, mx0, my0) {
    if (Abs(mx - mx0) < SNAP_MIN_TRAVEL && Abs(my - my0) < SNAP_MIN_TRAVEL)
        return ""
    Loop MonitorGetCount() {
        MonitorGet A_Index, &l, &t, &r, &b
        if (mx < l || mx >= r || my < t || my >= b)
            continue
        MonitorGetWorkArea A_Index, &wl, &wt, &wr, &wb
        half := (wr - wl) // 2
        if (my - t < SNAP_EDGE)
            return {kind: "top", x: wl, y: wt, w: wr - wl, h: wb - wt}
        if (mx - l < SNAP_EDGE)
            return {kind: "left", x: wl, y: wt, w: half, h: wb - wt}
        if (r - 1 - mx < SNAP_EDGE)
            return {kind: "right", x: wl + half, y: wt, w: half, h: wb - wt}
        return ""
    }
    return ""
}

; Shows (or moves, or hides) the preview: a click-through blue rectangle.
SnapPreview(zone) {
    global snapGui, snapKind
    kind := zone ? zone.kind : ""
    if (kind = snapKind)
        return
    snapKind := kind
    if !zone {
        if snapGui
            snapGui.Hide()
        return
    }
    if !snapGui {
        snapGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 +E0x20")
        snapGui.BackColor := "7d82d9"
    }
    snapGui.Show("NA x" zone.x " y" zone.y " w" zone.w " h" zone.h)
    WinSetTransparent 70, snapGui
}

; The button went up: take the preview away and, in a zone, snap the window.
SnapFinish(hwnd, zone) {
    global snapGui, snapKind
    if snapGui {
        try snapGui.Destroy()
        snapGui := ""
    }
    snapKind := ""
    if !zone
        return
    Sleep 150                               ; let GlazeWM take in where the drag ended
    id := GlazeInfo(hwnd, &state, PrefetchWindows())
    if !id
        return
    if (zone.kind = "top") {
        Run GLAZE ' command --id ' id ' set-fullscreen', , "Hide"
        return
    }
    ; No `move --direction` after it: on the first tile of a workspace that moves
    ; the window to the next monitor (it did, in a test). It lands beside the
    ; focused window of the workspace it was dropped on.
    Run GLAZE ' command --id ' id ' set-tiling', , "Hide"
}

FocusMonitorOfEmptyClick() {
    static lastRun := 0
    CoordMode "Mouse", "Screen"
    MouseGetPos &mx, &my, &hwnd
    cls := ""
    try cls := WinGetClass("ahk_id " hwnd)
    if (cls != "Progman" && cls != "WorkerW")
        return                              ; a real window was clicked
    if (A_TickCount - lastRun < 300)
        return
    lastRun := A_TickCount
    ; GlazeWM numbers the monitors left to right.
    lefts := []
    pos := ""
    Loop MonitorGetCount() {
        MonitorGet A_Index, &l, &t, &r, &b
        lefts.Push(l)
        if (mx >= l && mx < r && my >= t && my < b)
            pos := l
    }
    if (pos = "")
        return
    index := 0
    for l in lefts
        if (l < pos)
            index++
    Run GLAZE ' command focus --monitor ' index, , "Hide"
}

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
            if (Abs(mx - mx0) < DRAG_THRESHOLD && Abs(my - my0) < DRAG_THRESHOLD) {
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
        if started
            SnapPreview(SnapZoneAt(mx, my, mx0, my0))
        if (A_TickCount - began > 30000)
            break                           ; safety brake
        ; One move per composed frame (DWM ticks at the fastest monitor, 240 Hz
        ; here): block until the next frame instead of flooding SetWindowPos.
        DllCall("dwmapi\DwmFlush")
    }
    DllCall("winmm\timeEndPeriod", "UInt", 1)

    if started {
        SnapFinish(hwnd, SnapZoneAt(mx, my, mx0, my0))
        return
    }
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
    global winHeld, lastRClick
    winHeld := true
    CoordMode "Mouse", "Screen"
    SetWinDelay -1
    MouseGetPos &mx, &my, &hwnd
    if !CanMove(hwnd)
        return

    ; A press that does not move is a click: two close ones minimize the window.
    ; Floating the window waits for the first real movement.
    moved := false
    while rHeld && winHeld {
        MouseGetPos &nx, &ny
        if (Abs(nx - mx) >= DRAG_THRESHOLD || Abs(ny - my) >= DRAG_THRESHOLD) {
            moved := true
            break
        }
        Sleep 1
    }
    if !moved {
        if (A_TickCount - lastRClick < DOUBLE_CLICK_MS) {
            lastRClick := 0
            MinimizeWindow(hwnd)
        } else {
            lastRClick := A_TickCount
        }
        return
    }
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


; Win + double right click: minimize. GlazeWM's own command when it manages the
; window (it keeps its books right), the plain Windows one otherwise.
MinimizeWindow(hwnd) {
    id := GlazeInfo(hwnd, &state)
    if id
        Run GLAZE ' command --id ' id ' set-minimized', , "Hide"
    else
        try WinMinimize "ahk_id " hwnd
}

; Win + middle click: ask the window under the cursor to close.
CloseWindowUnderCursor() {
    CoordMode "Mouse", "Screen"
    MouseGetPos , , &hwnd
    if !CanMove(hwnd)
        return
    id := GlazeInfo(hwnd, &state)
    if id
        Run GLAZE ' command --id ' id ' close', , "Hide"
    else
        try WinClose "ahk_id " hwnd
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
    ; cmd /c strips the outer quotes of the line, so the quoted exe path and the
    ; quoted redirect target both need one more pair around everything.
    Run A_ComSpec ' /c "' GLAZE ' query windows > "' tmp '""', , "Hide", &pid
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
