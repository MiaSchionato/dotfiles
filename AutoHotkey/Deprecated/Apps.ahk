#Requires AutoHotkey v2.0

app := A_Args[1]
Run("komorebic focus-named-workspace " app, , "Hide")

Switch app 
{
    Case "Premiere":
    if not WinExist("ahk_exe Adobe Premiere Pro.exe")
        Run("C:\Program Files\Adobe\Adobe Premiere Pro 2026\Adobe Premiere Pro.exe", , "Hide")

    Case "Resolve":
    if not WinExist("ahk_exe Resolve.exe")
        Run("C:\Program Files\Blackmagic Design\DaVinci Resolve\Resolve.exe", , "Hide")

    Case "AfterFX":
    if not WinExist("ahk_exe AfterFX.exe")
        Run("C:\Program Files\Adobe\Adobe After Effects 2026\Support Files\AfterFX.exe", , "Hide")

    Case "Browser":
    if not WinExist("ahk_exe zen.exe")
        Run("C:\Program Files\Zen Browser\zen.exe", , "Hide")

    Case "Nvim":
    if not WinExist("ahk_exe nvim-wezterm.exe")
        Run("C:\Program Files\WezTerm\nvim-wezterm.exe start -- nvim")
}

ExitApp
