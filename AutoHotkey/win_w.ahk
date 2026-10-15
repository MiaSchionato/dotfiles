; Win + W: close what is in front, the way that app likes. kanata sends F22 for it.
; In a browser or an editor with tabs / sequences, Ctrl + W closes the tab (Alt + F4
; would close the whole app); anywhere else it is Alt + F4.
; (kanata used to switch to a layer for this by the app in focus, through the yasb
; widget vim_mode, which is not in the bar any more: this does it by itself.)
CTRL_W_APPS := ["zen.exe", "Adobe Premiere Pro.exe", "filmcraft.exe"]

; The keys Win + W sends for a process: kept apart from the sending so it can be tested
; without pressing anything in a real window.
WinWKeys(process) {
    for app in CTRL_W_APPS
        if (process = app)
            return "^w"
    return "!{F4}"
}

CloseOrCtrlW(process) {
    Send WinWKeys(process)
}

; CapsLock tap is Esc (kanata); inside Premiere and After Effects it has to be Delete. The
; yasb widget that switched kanata's layer for this is not in the bar any more, so here:
; in those two apps, Esc becomes Delete. kanata keeps sending a plain Esc, so if this
; script is not running nothing breaks except the Delete. The catch: the physical Esc key
; becomes Delete there too (Caps tap is the Esc of this keyboard).
ESC_IS_DELETE_APPS := ["Adobe Premiere Pro.exe", "AfterFX.exe"]

EscIsDeleteHere() {
    process := ""
    try process := WinGetProcessName("A")
    return EscIsDeleteIn(process)
}

EscIsDeleteIn(process) {
    for app in ESC_IS_DELETE_APPS
        if (process = app)
            return true
    return false
}
