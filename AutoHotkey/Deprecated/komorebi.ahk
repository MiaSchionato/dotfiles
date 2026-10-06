#Requires AutoHotkey v2.0

; =============================================================
;  komorebi - tiling window manager bindings
;
;  Keys follow the Hyprland config in the dotfiles repo wherever they
;  can, so the muscle memory carries over.
;
;  SHIFT ALWAYS MEANS "take this there". Plain key moves the focus,
;  Shift moves the window. That is why hjkl and the ,/. pair mirror
;  each other.
;
;  hjkl gets the moves INSIDE the layout because those need four
;  directions. Monitors only need two -- there is no monitor above or
;  below -- so they live on the ,/. pair, and cycle round.
;
;  komorebic-no-console.exe, not komorebic.exe: the latter flashes a
;  console window on every single hotkey. Full path because
;  komorebi\bin is not on PATH.
;
;  Every komorebic call spawns a process, which costs tens of
;  milliseconds. Fine for discrete keypresses, NOT fine for anything
;  in a loop -- see the note at the bottom about the mouse.
; =============================================================

#HotIf  ; make sure no context is inherited from another file

; ---------- escape hatches ----------
; Del and not Esc: Esc is reachable via a CapsLock tap, and a panic
; key should not sit on a key she retired.
;
; session-float-rule takes no arguments: it acts on the foreground
; window, so a misbehaving dialog needs no class or title to be
; identified. One key and it floats for the rest of the session.
; That list is also the data we later harden into applications.json.
#+Del::Komorebi("toggle-pause")            ; panic button, stops tiling
#+f::Komorebi("session-float-rule")        ; let go of the focused window
#+s::Komorebi("session-float-rules")       ; see what was let go of
#+c::Komorebi("clear-session-float-rules")

; ---------- window state ----------
#f::Komorebi("toggle-float")               ; float / tile this window
#m::Komorebi("toggle-maximize")            ; real maximize, not monocle

; ---------- focus and move, inside the layout ----------
; Win+L is usable because DisableLockWorkstation freed it, which is
; what let this layer stay on vim keys.
#h::Komorebi("focus left")
#j::Komorebi("focus down")
#k::Komorebi("focus up")
#l::Komorebi("focus right")

#+h::Komorebi("move left")
#+j::Komorebi("move down")
#+k::Komorebi("move up")
#+l::Komorebi("move right")

; ---------- monitors ----------
; cycle-* wraps around: moving right from the rightmost monitor lands
; on the leftmost one.
#,::Komorebi("cycle-monitor previous")
#.::Komorebi("cycle-monitor next")

#+,::Komorebi("cycle-move-to-monitor previous")
#+.::Komorebi("cycle-move-to-monitor next")

; ---------- workspaces ----------
; focus-workspace is relative to whichever monitor has focus, not
; global. With three monitors the same number does different things
; depending on where focus is -- which is why the app jumps in
; apps.ahk go by name instead.
;
; Ctrl+h/l walks one at a time, the way Super+Ctrl+H/L did in
; Hyprland. The numbers jump straight there.
#^h::Komorebi("cycle-workspace previous")
#^l::Komorebi("cycle-workspace next")

#1::Komorebi("focus-workspace 0")
#2::Komorebi("focus-workspace 1")
#3::Komorebi("focus-workspace 2")
#4::Komorebi("focus-workspace 3")
#5::Komorebi("focus-workspace 4")

#+1::Komorebi("move-to-workspace 0")
#+2::Komorebi("move-to-workspace 1")
#+3::Komorebi("move-to-workspace 2")
#+4::Komorebi("move-to-workspace 3")
#+5::Komorebi("move-to-workspace 4")


Komorebi(args) {
    static EXE := "C:\Program Files\komorebi\bin\komorebic-no-console.exe"
    try
        Run '"' EXE '" ' args, , "Hide"
    catch as e
        TrayTip("komorebi", "Failed: " args "`n" e.Message)
}

