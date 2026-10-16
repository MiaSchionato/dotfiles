; =============================================================
;  EXPERIMENT (2026-10-16): let Windows move the window, GlazeWM does the rest.
;
;  Ctrl + Win + left button, held on any part of a window, drags it as if it
;  were held by its title bar: the script only tells the window "the caption was
;  clicked" (WM_NCLBUTTONDOWN / HTCAPTION), so Windows runs its own move loop and
;  GlazeWM sees the same events as with a real title-bar drag (a tiled window
;  dropped on another one swaps/inserts there). Nothing else in windows.ahk is
;  touched: this file runs on its own, the Win + drag of windows.ahk is unchanged.
;
;  Start:  AutoHotkey64.exe native_drag_test.ahk      Stop: tray icon > Exit
; =============================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
SendMode "Event"

; The desktop and the taskbar are not windows to move.
IGNORED_CLASSES := Map("Progman", 1, "WorkerW", 1, "Shell_TrayWnd", 1, "Shell_SecondaryTrayWnd", 1)

^#LButton:: NativeDrag()

NativeDrag() {
    MouseGetPos &x, &y, &hover
    if !hover
        return
    top := DllCall("GetAncestor", "Ptr", hover, "UInt", 2, "Ptr")     ; GA_ROOT
    if !top || IGNORED_CLASSES.Has(WinGetClass("ahk_id " top))
        return
    lParam := (y << 16) | (x & 0xFFFF)                                ; screen coordinates
    DllCall("SetForegroundWindow", "Ptr", top)
    PostMessage 0xA1, 2, lParam, , "ahk_id " top                      ; WM_NCLBUTTONDOWN, HTCAPTION
    KeyWait "LButton"
}
