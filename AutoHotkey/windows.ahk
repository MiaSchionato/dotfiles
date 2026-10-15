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
;  GlazeWM acts on any window by id (`command --id`), so, unlike komorebic,
;  the window does not have to be focused first. The commands go over its own
;  socket (glaze_ipc.ahk): a kept connection, about 0.2 ms a call.
; =============================================================

#HotIf
#SingleInstance Force
#Include glaze_ipc.ahk          ; GlazeWM's socket (no CLI process, no helper script)
#Include glaze_workspaces.ahk   ; F13-F17: workspace shortcuts with logic (kanata sends them)
#Include win_w.ahk              ; F22: Win + W (Ctrl+W in Zen / Premiere / Filmcraft, else Alt+F4)

F22:: CloseOrCtrlW(WinGetProcessName("A"))

DOUBLE_CLICK_MS := 350      ; two clicks closer than this are a double click
DRAG_THRESHOLD := 3         ; px before a press counts as a drag: a hand always
                            ; moves the mouse a pixel or two inside a click
lastClick := 0
lastRClick := 0
winHeld := false
lHeld := false
rHeld := false
glazeRect := []             ; x, y, width, height of the last window GlazeInfo found

; Connect now, not on the first Win + click; the connection is remade by itself
; if GlazeWM restarts.
Glaze.Connect()
OnExit((*) => Glaze.Close())

~F24:: global winHeld := true
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
; Polled (every 25 ms) instead of a ~LButton hotkey: a hotkey on a mouse button
; installs AutoHotkey's mouse hook, which adds lag to every pointer movement (the
; "delay while dragging" Mia noticed right after this was added).
SetTimer WatchDesktopClick, 25


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
snapMonitors := []

; The zone under the cursor: {kind: "left" | "right" | "top", x, y, w, h, left,
; right} (the preview rectangle in the monitor's work area, and the monitor's
; left and right edges), or "" for none.
SnapZoneAt(mx, my, mx0, my0) {
    global snapMonitors
    if (Abs(mx - mx0) < SNAP_MIN_TRAVEL && Abs(my - my0) < SNAP_MIN_TRAVEL)
        return ""
    for m in snapMonitors {
        l := m[1], t := m[2], r := m[3], b := m[4]
        if (mx < l || mx >= r || my < t || my >= b)
            continue
        wl := m[5], wt := m[6], wr := m[7], wb := m[8]
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

; The monitors' rectangles and work areas, read once when a drag starts (the calls
; walk the monitors every time, too slow for each frame).
ReadSnapMonitors() {
    global snapMonitors
    snapMonitors := []
    Loop MonitorGetCount() {
        MonitorGet A_Index, &l, &t, &r, &b
        MonitorGetWorkArea A_Index, &wl, &wt, &wr, &wb
        snapMonitors.Push([l, t, r, b, wl, wt, wr, wb])
    }
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
        ; -DPIScale: the rectangle is in screen pixels, not scaled by the system DPI (it
        ; overshot the half of the monitor when scaled).
        snapGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 +E0x20 -DPIScale")
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
    if zone
        GlazeSnap(hwnd, zone.kind)
}

; Snap over the socket, the commands back to back (a process per command left the
; tile on the wrong side for a moment):
;   top            set-fullscreen
;   left / right   set-tiling, then, if the window landed on the wrong side of the
;                  other tiles of its monitor, the `move --direction` swaps that
;                  put it on the side asked (one per tile it has to pass).
; GlazeWM puts a window back in tiling at its old slot (or beside the last focused
; tile), not where it was dropped, hence the swaps. Alone on its monitor there is
; no side, and a move would only send it to the next monitor: nothing is done.
GlazeSnap(hwnd, kind) {
    Sleep 40                                ; GlazeWM takes in where the drag ended
    id := GlazeInfo(hwnd, &state)
    if !id
        return
    if (kind = "top") {
        Glaze.Send("command --id " id " set-fullscreen")
        return
    }
    Glaze.Send("command --id " id " set-tiling")
    json := Glaze.Ask("query monitors")     ; the answer comes after the set-tiling
    for monitor in StrSplit(json, '{"type":"monitor"') {
        mineCentre := ""
        others := []
        for chunk in StrSplit(monitor, '{"type":"window"') {
            if !RegExMatch(chunk, '"handle":(\d+)', &mh)
                continue
            if !RegExMatch(chunk, '"state":\{"type":"(\w+)"', &ms) || ms[1] != "tiling"
                continue
            if !InStr(chunk, '"displayState":"shown"')
                continue                    ; a window on a workspace that is not on screen
            if !RegExMatch(chunk, '"width":(-?\d+),"height":-?\d+,"x":(-?\d+),"y":', &mg)
                continue
            centre := Integer(mg[2]) + Integer(mg[1]) / 2
            if (mh[1] = hwnd)
                mineCentre := centre
            else
                others.Push(centre)
        }
        if (mineCentre = "")
            continue
        passes := 0
        for centre in others
            if (kind = "left" ? centre < mineCentre : centre > mineCentre)
                passes++
        Loop passes
            Glaze.Send("command --id " id " move --direction " kind)
        return
    }
}

WatchDesktopClick() {
    static wasDown := false
    down := GetKeyState("LButton", "P")
    pressed := down && !wasDown
    wasDown := down
    if pressed
        FocusMonitorOfEmptyClick()
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
    Glaze.Send("command focus --monitor " index)
}

DragOrToggle() {
    global lastClick, winHeld
    winHeld := true
    CoordMode "Mouse", "Screen"
    SetWinDelay -1
    MouseGetPos &mx0, &my0, &hwnd
    if !CanMove(hwnd)
        return
    try WinActivate "ahk_id " hwnd          ; focus and raise it
    DllCall("winmm\timeBeginPeriod", "UInt", 1)
    started := false
    lastX := lastY := ""
    snapX := snapY := ""
    began := A_TickCount
    while winHeld && lHeld {
        MouseGetPos &mx, &my
        if !started {
            if (Abs(mx - mx0) < DRAG_THRESHOLD && Abs(my - my0) < DRAG_THRESHOLD) {
                Sleep 1
                continue
            }
            started := true
            ReadSnapMonitors()
            FloatIfTiled(hwnd)
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
        if (started && (mx != snapX || my != snapY)) {
            snapX := mx, snapY := my
            SnapPreview(SnapZoneAt(mx, my, mx0, my0))
        }
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
        id := GlazeInfo(hwnd, &state)
        if id
            Glaze.Send("command --id " id " toggle-floating")
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
    FloatIfTiled(hwnd)
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
        Glaze.Send("command --id " id " set-minimized")
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
        Glaze.Send("command --id " id " close")
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
; The rectangle is GlazeWM's own (physical pixels), not WinGetPos's: this script
; is DPI-aware for the system scale, and on a monitor with another scale (the
; right one) its coordinates are not GlazeWM's, so the window used to land a
; hundred pixels from where it was grabbed.
FloatIfTiled(hwnd) {
    global glazeRect
    id := GlazeInfo(hwnd, &state)
    if (!id || state != "tiling")
        return
    ; Waits for the answer: the window has to be floating before it is moved.
    if (glazeRect.Length = 4)
        Glaze.Ask("command --id " id " set-floating --centered=false --x-pos " glazeRect[1]
            . " --y-pos " glazeRect[2] " --width " glazeRect[3] " --height " glazeRect[4])
    else
        Glaze.Ask("command --id " id " set-floating --centered=false")
}

; GlazeWM's container id of a window (its handle is the hwnd) and its state
; type (tiling / floating / minimized / fullscreen). "" when GlazeWM does not
; manage it.
GlazeInfo(hwnd, &state) {
    global glazeRect
    json := Glaze.Ask("query windows")
    state := ""
    for chunk in StrSplit(json, '{"type":"window"') {
        if !RegExMatch(chunk, '"handle":' hwnd '[,}]')
            continue
        if RegExMatch(chunk, '"id":"([^"]+)"', &mi) && RegExMatch(chunk, '"state":\{"type":"(\w+)"', &ms) {
            state := ms[1]
            glazeRect := []
            if RegExMatch(chunk, '"width":(-?\d+),"height":(-?\d+),"x":(-?\d+),"y":(-?\d+)', &mg)
                glazeRect := [mg[3], mg[4], mg[1], mg[2]]   ; x, y, width, height
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
