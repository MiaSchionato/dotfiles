#Requires AutoHotkey v2.0

; =============================================================
;  accents - macOS-style dead keys
;
;    Alt+E  -> acute       (a e i o u)    Alt+I  -> circumflex
;    Alt+`  -> grave                      Alt+N  -> tilde (a o n)
;    Alt+C  -> c cedilla          Alt+Shift+C -> C cedilla
;
;  The same shortcuts work holding CapsLock instead of Alt, for apps
;  that don't get along with Alt (e.g. the Claude app, where Alt
;  toggles the menu bar). For an uppercase C cedilla: CapsLock first,
;  then Shift+C -- Shift before CapsLock is Delete.
;
;  E.g. Alt+E then Shift+A  ->  uppercase A with acute.
;  If the next key takes no accent, the mark is typed followed by the
;  key (nothing is swallowed, same as macOS).
; =============================================================

accentPending := false  ; an accent is waiting for its letter

!e::AccentAcute()
!`::AccentGrave()
!i::AccentCircumflex()
!n::AccentTilde()
!c::Send("{Text}ç")
!+c::Send("{Text}Ç")

; Off while an accent waits for its letter: with CapsLock still held,
; the "e" of an e-acute would fire this layer again instead of
; reaching the accent.
; SC029 is the physical key left of 1. Written as "`::" the grave
; accent would start the line, where it is AHK's escape character.
#HotIf GetKeyState("CapsLock", "P") && !accentPending
e::AccentAcute()
SC029::AccentGrave()
i::AccentCircumflex()
n::AccentTilde()
c::Send("{Text}ç")
+c::Send("{Text}Ç")
#HotIf


AccentAcute() {
    Accent("´", Map("a","á", "e","é", "i","í", "o","ó", "u","ú",
                    "A","Á", "E","É", "I","Í", "O","Ó", "U","Ú"))
}

AccentGrave() {
    Accent("``", Map("a","à", "e","è", "i","ì", "o","ò", "u","ù",
                     "A","À", "E","È", "I","Ì", "O","Ò", "U","Ù"))
}

AccentCircumflex() {
    Accent("^", Map("a","â", "e","ê", "i","î", "o","ô", "u","û",
                    "A","Â", "E","Ê", "I","Î", "O","Ô", "U","Û"))
}

AccentTilde() {
    Accent("~", Map("a","ã", "o","õ", "n","ñ",
                    "A","Ã", "O","Õ", "N","Ñ"))
}

; Waits for the next key and types the accented letter.
Accent(mark, letters) {
    global accentPending
    accentPending := true
    ih := InputHook("L1 T2")
    ih.Start()
    ih.Wait()
    accentPending := false
    key := ih.Input

    if (key = "")               ; timed out: just the mark
        Send("{Text}" mark)
    else if letters.Has(key)    ; accented letter
        Send("{Text}" letters[key])
    else                        ; no accent: mark + key
        Send("{Text}" mark key)
}
