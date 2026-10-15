; =============================================================
;  Workspace shortcuts with logic, over GlazeWM's socket (glaze_ipc.ahk)
;
;  kanata sends F13-F17 for them (the Win layer; no process, no script): about 1 ms.
;
;    F13  Win + Space        go to Editor (every video editor); again: back
;    F14  Win + M            go to Motion (every motion app); again: back
;    F15  Win + Backspace    go to Scratchpad; again: back
;    F16  Win + B            go to Browser (opens Zen if it is not running); again: back
;    F17  Win + N            go to Nvim (opens it if it is not running); again: back
;    F18  Win + P            go to Photo (Photoshop, Affinity, Photocraft); again: back
;    Alt  + F13..F17         PULL the workspace to the monitor in focus (Win + Alt + key):
;                            F13 Editor, F14 Motion, F15 Scratchpad, F16 Browser, F17 Nvim
;    Ctrl + F13..F15         send the workspace in focus to monitor 1 / 2 / 3, left to
;                            right (Win + Shift + 1 / 2 / 3)
;
;  FREE workspaces (no bind_to_monitor in the GlazeWM config) come to the monitor in focus
;  when called, like a scratchpad: GlazeWM alone would show a hidden one back on the
;  monitor it was last on. If one is on screen on another monitor, calling it only goes
;  there; pulling (Alt) brings it here. Editor and Motion are tied to the centre monitor.
; =============================================================

F13:: GoWorkspace("Editor")
F14:: GoWorkspace("Motion")
F15:: GoWorkspace("Scratchpad")
F16:: GoWorkspace("Browser", "zen.exe", '"C:\Program Files\Zen Browser\zen.exe"')
F18:: GoWorkspace("Photo")
!F18:: PullWorkspace("Photo")
F17:: GoWorkspace("Nvim", "nvim-wezterm.exe", '"C:\Program Files\WezTerm\nvim-wezterm.exe" start -- wsl --cd ~ -e fish -c nvim')
!F13:: PullWorkspace("Editor")
!F14:: PullWorkspace("Motion")
!F15:: PullWorkspace("Scratchpad")
!F16:: PullWorkspace("Browser")
!F17:: PullWorkspace("Nvim")
^F13:: SendWorkspaceToMonitor(1)
^F14:: SendWorkspaceToMonitor(2)
^F15:: SendWorkspaceToMonitor(3)


; The monitors, left to right: [{focus, workspaces: [{name, shown, focus}]}], read from
; `query monitors`. A monitor's own fields come AFTER its workspaces in that JSON.
GlazeMonitors() {
    json := Glaze.Ask("query monitors")
    found := []
    for chunk in StrSplit(json, '{"type":"monitor"') {
        if !RegExMatch(chunk, '"hasFocus":(true|false),"width":\d+,"height":\d+,"x":(-?\d+)', &mm)
            continue
        mon := {x: Integer(mm[2]), focus: (mm[1] = "true"), workspaces: []}
        for ws in StrSplit(chunk, '{"type":"workspace"') {
            if !RegExMatch(ws, '"name":"([^"]+)"', &mn)
                continue
            if !RegExMatch(ws, '"hasFocus":(true|false),"isDisplayed":(true|false)', &mf)
                continue
            mon.workspaces.Push({name: mn[1], focus: (mf[1] = "true"), shown: (mf[2] = "true")})
        }
        found.Push(mon)
    }
    loop found.Length - 1 {                 ; left to right (insertion sort on x)
        i := A_Index + 1
        cur := found[i]
        j := i - 1
        while (j >= 1 && found[j].x > cur.x) {
            found[j + 1] := found[j]
            j--
        }
        found[j + 1] := cur
    }
    return found
}

; Workspaces that follow the monitor in focus (the others stay on their own monitor).
FREE_WORKSPACES := Map("Browser", 1, "Nvim", 1, "Scratchpad", 1, "Claude", 1, "WhatsApp", 1)

; Index (1 = leftmost) of the monitor in focus, of the one that shows `name` (0: not on
; screen) and of the one the workspace lives on (0: it does not exist yet), plus the
; workspace in focus.
FindWorkspace(mons, name, &focused, &shownOn, &livesOn, &focusedName) {
    focused := 0, shownOn := 0, livesOn := 0, focusedName := ""
    for i, mon in mons {
        if mon.focus
            focused := i
        for ws in mon.workspaces {
            if (ws.name = name) {
                livesOn := i
                if ws.shown
                    shownOn := i
            }
            if ws.focus
                focusedName := ws.name
        }
    }
}

; Go to the workspace; if it is the one in focus already, back to the previous one. A free
; workspace that is hidden comes to the monitor in focus; `launch` (a command line) runs
; when `process` is not running, to open the app of that workspace.
GoWorkspace(name, process := "", launch := "") {
    FindWorkspace(GlazeMonitors(), name, &here, &shownOn, &livesOn, &current)
    if (current = name) {
        Glaze.Send("command focus --recent-workspace")
        return
    }
    if (FREE_WORKSPACES.Has(name) && !shownOn)
        BringHere(name, here, livesOn)
    else
        Glaze.Send("command focus --workspace " name)
    if (process != "" && !ProcessExist(process))
        Run launch
}

; Bring the workspace to the monitor in focus, wherever it is (on screen or hidden).
PullWorkspace(name) {
    FindWorkspace(GlazeMonitors(), name, &here, &shownOn, &livesOn, &current)
    BringHere(name, here, shownOn ? shownOn : livesOn)
}

; Focus the workspace (GlazeWM shows it on the monitor it lives on, or on this one when it
; is new) and, when that is another monitor than `here`, move it over, one monitor at a time.
BringHere(name, here, from) {
    Glaze.Send("command focus --workspace " name)
    if (!here || !from || here = from)
        return
    direction := (from < here) ? "right" : "left"
    loop Abs(from - here)
        Glaze.Send("command move-workspace --direction " direction)
}

; Send the workspace in focus to monitor number `target` (1 = leftmost), one monitor at a
; time. Its windows go with it; what was on that monitor stays on its workspace, hidden.
SendWorkspaceToMonitor(target) {
    mons := GlazeMonitors()
    here := 0
    for i, mon in mons
        if mon.focus
            here := i
    if (!here || target > mons.Length || target = here)
        return
    direction := (target > here) ? "right" : "left"
    loop Abs(target - here)
        Glaze.Send("command move-workspace --direction " direction)
}
