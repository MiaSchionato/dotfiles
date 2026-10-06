#Requires AutoHotkey v2.0

; =============================================================
;  resolve - jog with the MX Creative dial, DaVinci only
;
;    horizontal scroll  ->  left / right arrows
;    automatic K when playback is running
;
;  In Logi Options+, in the Resolve profile, the dial is mapped to
;  HORIZONTAL SCROLL. The default profile can use anything else
;  (volume, for example): these shortcuts only exist while Resolve is
;  in the foreground.
;
;  Why horizontal and not volume, since both work fine: because of
;  how each fails. If this script isn't running, events pass through
;  raw -- with horizontal, Resolve scrolls sideways and nothing is
;  lost; with volume, the system sound jumps around while you edit.
;  Options+ also tends to draw its own OSD on volume changes, which
;  would flash on every jog detent.
;
;  Already tried and dropped:
;    Ctrl+Alt+PageUp/Dn  unusable -- SIX events per detent (ctrl,
;                        alt and key, down and up) versus ONE for a
;                        scroll event.
;    F13 / F14           never turned out to be needed.
;    vertical wheel      worked, but stole scrolling from every panel
;                        (media pool, nodes, inspector).
;    K by timing         detecting the start of a gesture by a 400 ms
;                        pause. Doesn't work: timing can't tell a
;                        micro-adjustment from navigation. Replaced by
;                        tracking the transport state.
; =============================================================

isPlaying := false  ; is playback running?

#HotIf WinActive("ahk_exe Resolve.exe")

; Track the transport to know whether playback is running. The "~"
; lets the keys through to Resolve as usual.
~Space::SetTransport("toggle")  ; play/pause
~l::SetTransport(true)          ; play forward
~j::SetTransport(true)          ; play backward
~k::SetTransport(false)         ; stop

WheelLeft::Jog("Right")
WheelRight::Jog("Left")

#HotIf


; K is only sent when playback is actually running, and only once --
; on the first dial turn after play. The time between events isn't
; used to guess where a gesture starts: a pause can't tell "about to
; navigate" from "micro-adjustment" or "paused mid long scroll", which
; is why the earlier attempt failed.
;
; Known limit: if playback is started from the UI play button or the
; Console's transport, AHK sees no key and doesn't know. Erring that
; way is harmless -- it falls back to the old behavior.
; Hotkey bodies are functions: without "global", assigning isPlaying
; would create a new local on every trigger. Hence this function.
SetTransport(v) {
    global isPlaying
    isPlaying := (v = "toggle") ? !isPlaying : v
}

Jog(arrow) {
    global isPlaying
    if isPlaying {
        Send "k"
        isPlaying := false
    }
    Send "{" arrow "}"
}
