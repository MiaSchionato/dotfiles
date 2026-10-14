#Requires AutoHotkey v2.0

; NOT IN USE (Mia, 2026-10-14: "not now, maybe in the future"). Kept here, not
; loaded by anything. To try it again: add   #Include alttab-all-windows.ahk
; at the end of windows.ahk (it uses GLAZE, GlazeWM's CLI path, and winHeld,
; both defined there) and restart AutoHotkey.
;
; =============================================================
;  Alt+Tab over ALL the windows, workspaces included
;
;  Windows' own Alt+Tab skips the windows GlazeWM hides on the workspaces that
;  are not on screen (they are "cloaked"). This switcher lists every window
;  GlazeWM manages, most recently used first, with its workspace; Tab / Shift+Tab
;  step through them, letting go of Alt goes there (GlazeWM switches workspace),
;  Esc cancels. Win+Tab stays Windows' own switcher (kanata sends it as
;  Alt+Tab, but with F24 held, i.e. winHeld, and this one stays out of it).
;  Colours: the ethereal palette.
; =============================================================

swGui := ""
swRows := []
swItems := []
swIdx := 0
swOpen := false
altUp := true

#HotIf !winHeld
!Tab:: AltTabOpen(1)
!+Tab:: AltTabOpen(-1)
#HotIf swOpen
*Esc:: AltTabClose(false)
#HotIf
~LAlt up:: AltTabAltUp()


AltTabAltUp() {
    global altUp, swOpen
    altUp := true
    if swOpen
        AltTabClose(true)
}

AltTabOpen(dir) {
    global swOpen, swItems, swIdx, altUp
    if swOpen {
        AltTabStep(dir)
        return
    }
    altUp := false
    items := CollectWindows()
    if (items.Length < 2)
        return                              ; nothing to switch to
    swItems := items
    swIdx := (dir > 0) ? 2 : items.Length   ; 1 is where you already are
    swOpen := true
    if altUp {                              ; a quick tap: Alt is already up
        AltTabClose(true)
        return
    }
    AltTabBuild()
    if altUp                                ; ... or went up while drawing
        AltTabClose(true)
}

AltTabStep(dir) {
    global swIdx, swItems, swRows
    n := Min(swItems.Length, swRows.Length)
    if (n < 1)
        return
    swIdx := Mod(swIdx - 1 + dir + n, n) + 1
    AltTabPaint()
}

AltTabClose(commit) {
    global swOpen, swGui, swItems, swIdx
    if !swOpen
        return
    swOpen := false
    try swGui.Destroy()
    if (commit && swIdx >= 1 && swIdx <= swItems.Length) {
        it := swItems[swIdx]
        try {                               ; the window may be gone by now
            if (WinGetMinMax("ahk_id " it.hwnd) = -1)
                WinRestore "ahk_id " it.hwnd
        }
        Run GLAZE ' command focus --container-id ' it.id, , "Hide"
    }
}

AltTabPaint() {
    global swRows, swIdx
    for i, row in swRows {
        if (i = swIdx) {
            row.Opt("Background7d82d9")
            row.SetFont("cffffff")
        } else {
            row.Opt("Background060B1E")
            row.SetFont("cffcead")
        }
        row.Redraw()
    }
}

AltTabBuild() {
    global swGui, swRows, swItems
    g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000 +Border")  ; no focus
    g.BackColor := "060B1E"
    g.MarginX := 8
    g.MarginY := 8
    g.SetFont("s11 cffcead", "Segoe UI")
    rows := []
    for i, it in swItems {
        if (i > 12)
            break
        rows.Push(g.Add("Text", "w660 h28 +0x200 Background060B1E", "  " it.label))
    }
    swGui := g
    swRows := rows
    AltTabPaint()
    g.Show("NA Hide AutoSize")
    g.GetPos(, , &w, &h)
    CoordMode "Mouse", "Screen"
    MouseGetPos &mx, &my
    left := 0, top := 0, right := A_ScreenWidth, bottom := A_ScreenHeight
    Loop MonitorGetCount() {
        MonitorGet A_Index, &l, &t, &r, &b
        if (mx >= l && mx < r && my >= t && my < b) {
            left := l, top := t, right := r, bottom := b
            break
        }
    }
    g.Show("NA x" (left + (right - left - w) // 2) " y" (top + (bottom - top - h) // 2))
}

; Every window GlazeWM manages (hidden workspaces included), most recently used
; first. Each: {id, hwnd, label}. `query monitors` lists the workspaces and,
; inside each, its windows, so a window belongs to the last workspace read.
CollectWindows() {
    tmp := A_Temp "\glazewm-all.json"
    try FileDelete tmp
    RunWait A_ComSpec ' /c "' GLAZE ' query monitors > "' tmp '""', , "Hide"
    json := ""
    try json := FileRead(tmp)
    z := Map()
    for i, h in WinGetList()
        z[h] := i
    items := []
    ws := ""
    pos := 1
    while RegExMatch(json, '"type":"workspace","id":"[^"]*","name":"([^"]*)"|"type":"window","id":"([^"]*)"', &m, pos) {
        pos := m.Pos + m.Len
        if (m[2] = "") {
            ws := m[1]
            continue
        }
        rest := SubStr(json, pos, 3000)
        if !RegExMatch(rest, '"handle":(\d+),"title":"((?:[^"\\]|\\.)*)","className":"[^"]*","processName":"([^"]*)"', &d)
            continue
        hwnd := Integer(d[1])
        if !WinExist("ahk_id " hwnd)        ; closed, or hidden by its own app
            continue
        title := JsonText(d[2])
        proc := d[3]
        if (title = "")
            title := proc
        if (StrLen(title) > 70)
            title := SubStr(title, 1, 69) "…"
        items.Push({id: m[2], hwnd: hwnd, z: z.Has(hwnd) ? z[hwnd] : 100000 + items.Length,
                    label: proc "  ·  " title "   [" ws "]"})
    }
    ; most recently used first (EnumWindows order is the z-order)
    n := items.Length
    Loop n - 1 {
        i := A_Index + 1
        cur := items[i]
        j := i - 1
        while (j >= 1 && items[j].z > cur.z) {
            items[j + 1] := items[j]
            j--
        }
        items[j + 1] := cur
    }
    return items
}

JsonText(s) {
    s := StrReplace(s, '\"', '"')
    s := StrReplace(s, "\\", "\")
    s := StrReplace(s, "\/", "/")
    while RegExMatch(s, "\\u([0-9a-fA-F]{4})", &u)
        s := StrReplace(s, u[0], Chr("0x" u[1]))
    return s
}
