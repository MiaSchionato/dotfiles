#Requires AutoHotkey v2.0
#SingleInstance Force

; A remapped mouse wheel fires many hotkeys per second. The default
; limit (70 per 2 s) pops the "N hotkeys have been received" warning.
; 500 still catches a real runaway loop, but human scrolling never
; gets there.

;; A_MaxHotkeysPerInterval := 500  ; a variable in v2, not a directive

; =============================================================
;  main - loads everything into a single process (one tray icon).
;  This is the file that starts with Windows.
;
;  pan.ahk calls IsButtonDown from windows.ahk, so it doesn't run on
;  its own. device-probe.ahk is NOT included: it's a diagnostic tool,
;  run by hand when needed.
; =============================================================

; #Include accents.ahk
; #Include pan.ahk
; #Include shortcuts.ahk
; #Include resolve.ahk
; #Include windows.ahk
; #Include komorebi.ahk
; #Include apps.ahk
; #Include komorebi.ahk
#Include newShortcuts.ahk
