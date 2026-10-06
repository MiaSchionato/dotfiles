#Requires AutoHotkey v2.0

#HotIf WinActive("ahk_exe zen.exe")
F14::Send("^w")

#HotIf
F14::Run("komorebic close", , "Hide")


#HotIf WinActive("ahk_exe Adobe Premiere Pro.exe")
F15::Send("{Delete}")

#HotIf
F15::Send("{Esc}")
