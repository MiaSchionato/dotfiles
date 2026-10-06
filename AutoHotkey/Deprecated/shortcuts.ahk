#Requires AutoHotkey v2.0

; =============================================================
;  shortcuts - macOS-style keyboard remaps
;
;  Order matters: specific #HotIf blocks come first and global
;  shortcuts after, otherwise the global one wins and the specific
;  one never fires.
; =============================================================

; ---------- initialization (must stay at the top) ----------
SetCapsLockState "AlwaysOff"
capsSentDelete := false  ; shared by the two CapsLock handlers
capsIsDown := false      ; CapsLock already down? (ignores auto-repeat)
winDownAt := 0           ; time of the first Win keydown (0 = released)

; ---------- Zen browser ----------
#HotIf WinActive("ahk_exe zen.exe")
#w::Send "^w"  ; closes the tab, not the browser
#q::CloseActiveWindow()
#HotIf


; ---------- Premiere / After Effects: CapsLock tap = Delete ----------
; ahk_exe takes no list: one WinActive per app, joined with ||.
#HotIf WinActive("ahk_exe Adobe Premiere Pro.exe") || WinActive("ahk_exe AfterFX.exe")
; Only on RELEASE, and only after a clean tap. It used to be
; "*CapsLock::Delete", which fired on press and auto-repeated --
; holding CapsLock deleted in bursts and the key couldn't be used as
; a layer (hjkl, right click) inside these apps.
; This variant must come BEFORE the global one further down.
*CapsLock up:: {
    global capsSentDelete, capsIsDown
    if (A_PriorKey = "CapsLock" && !capsSentDelete)
        Send "{Delete}"
    capsSentDelete := false
    capsIsDown := false
}
#HotIf

; ---------- Win = Cmd ----------
#a::^a
#c::^c
#x::^x
#v::^v
#t::^t
#z::^z
#+z::^+z
#w::CloseActiveWindow()
#Space::!Space  ; launcher


^v::#v  ; frees Ctrl+V for clipboard history (unaffected by the move)

; ---------- Win tap: no Start menu, opens the launcher ----------
; A dead mask key (vkE8, no function) is sent on every Win keydown.
; Windows no longer sees a clean tap and doesn't open Start, but the
; key still works as a modifier for everything else -- unlike
; "LWin::return", which suppressed it and killed the native Win
; shortcuts (Win+E, Win+L, Win+arrows).
;
; The mask goes out on EVERY keydown, auto-repeats included. Windows
; only looks at what happens between the LAST Win keydown and the
; keyup; an earlier version sent it only once (with KeyWait) and, when
; the key was held longer than ~half a second, the repeats buried it
; and Start opened.
;
; The F13 route was tried and abandoned on 2026-10-02. The idea was to
; remap LWin to F13 at driver level (Scancode Map) so Windows would
; never see a Win key at all. It never applied: correct value, correct
; registry path, full boot (type 0x0), with both AHK and Logi Options+
; closed -- and the key still reached Windows as Win. Windows' USB HID
; keyboard driver can ignore Scancode Map, and apparently does here.
; So this mask stays: it is what keeps the Start menu shut.
~LWin::OnWinDown()
~RWin::OnWinDown()

; Clean Win tap -> Alt+Space (app launcher). A_PriorKey still reads
; "LWin" if nothing was pressed in between; if Win was used as a
; modifier (Win+C, Win+Tab, Win+drag) it reads that key and the
; launcher doesn't open. Same tap detection as CapsLock.
; Opens only if released within 300 ms: holding longer means giving
; up, not asking for the launcher.
~LWin up::OnWinUp("LWin")
~RWin up::OnWinUp("RWin")


; winDownAt stores the time of the FIRST keydown. Repeats go through
; OnWinDown too but leave it alone -- otherwise the time would count
; from the last repeat and never pass the limit.
OnWinDown() {
    global winDownAt
    Send "{Blind}{vkE8}"
    if !winDownAt
        winDownAt := A_TickCount
}

OnWinUp(key) {
    global winDownAt
    quickTap := winDownAt && (A_TickCount - winDownAt < 300)
    winDownAt := 0
    if (A_PriorKey = key && quickTap)
        Send "!{Space}"
}

; ---------- virtual desktops (vim: h left, l right) ----------
^h::#^Left
^l::#^Right

; ---------- Win+Tab <-> Alt+Tab (swapped) ----------
; The AltTab action rejects a generic "#Tab"; it needs <# or >#.
<#Tab::AltTab
>#Tab::AltTab

!Tab:: {
    ; Shell COM method, no synthesized keys: the Alt being held
    ; doesn't interfere with modifier state.
    static shell := ComObject("Shell.Application")
    shell.WindowSwitcher()
    KeyWait "Tab"  ; absorbs auto-repeat: one trigger per press
}

; ---------- CapsLock: tap = Esc, Shift+ = Delete, hold = layer ----------
*CapsLock:: {
    global capsSentDelete, capsIsDown
    ; CapsLock auto-repeats come through here too. Without this guard,
    ; holding CapsLock and pressing Shift midway (for an uppercase
    ; accented letter or C cedilla) fired a Delete on the next repeat.
    if capsIsDown
        return
    capsIsDown := true
    if GetKeyState("Shift", "P") {
        capsSentDelete := true
        ; release Shift first: Shift+Delete in Explorer deletes
        ; permanently, skipping the Recycle Bin
        Send "{Blind}{LShift up}{RShift up}"
        Send "{Delete}"
    }
}

#HotIf GetKeyState("CapsLock", "P")
h::Left
j::Down
k::Up
l::Right
#HotIf

*CapsLock up:: {
    global capsSentDelete, capsIsDown
    if (A_PriorKey = "CapsLock" && !capsSentDelete)  ; plain tap: Esc
        Send "{Esc}"
    capsSentDelete := false
    capsIsDown := false
}

; CapsLock + left click          = right click   (see pan.ahk)
; CapsLock + e / ` / i / n / c   = accents       (see accents.ahk)

; =============================================================
;  functions
; =============================================================

; Closes the active window without sending any keys: resolves the
; HWND first and posts SC_CLOSE, the exact message the X button and
; Alt+F4 produce. With no Send, the Win key state can't interfere.
CloseActiveWindow() {
    hwnd := WinExist("A")
    if !hwnd
        return
    try PostMessage 0x0112, 0xF060, 0, , "ahk_id " hwnd  ; WM_SYSCOMMAND / SC_CLOSE
}
