#Requires AutoHotkey v2.0
#SingleInstance Force

; =============================================================
;  device-probe - which device did each wheel event come from?
;
;  Diagnostic tool, NOT part of main.ahk. Run it by hand, turn the
;  dial and the mouse wheel, and compare the hDevice values.
;
;  Uses Raw Input (WM_INPUT), which unlike regular hooks carries the
;  device identity. It only observes and blocks nothing.
;
;  It registers MICE only, on purpose: registering keyboards would
;  mean writing your keystrokes to a file.
;
;  Ctrl+Alt+Esc quits.
; =============================================================

eventCounts := Map()
lastDevice := 0

; --- register for mouse Raw Input ---
; RAWINPUTDEVICE: usUsagePage(2) usUsage(2) dwFlags(4) hwndTarget(8)
rid := Buffer(16, 0)
NumPut("UShort", 0x01, rid, 0)        ; Generic Desktop
NumPut("UShort", 0x02, rid, 2)        ; Mouse
NumPut("UInt",   0x00000100, rid, 4)  ; RIDEV_INPUTSINK: receive even without focus
NumPut("Ptr",    A_ScriptHwnd, rid, 8)
if !DllCall("RegisterRawInputDevices", "Ptr", rid, "UInt", 1, "UInt", 16) {
    WriteLog("RegisterRawInputDevices FAILED, error " A_LastError)
    ExitApp
}

WriteLog("")
WriteLog("===== probe started " FormatTime(, "HH:mm:ss") " =====")
ListDevices()
WriteLog("--- events (new line only when the device changes) ---")

OnMessage(0x00FF, OnRawInput)  ; WM_INPUT

TrayTip("Device probe running", "Turn the dial, then the mouse wheel. Ctrl+Alt+Esc quits.")

^!Esc::ExitApp


OnRawInput(wParam, lParam, msg, hwnd) {
    global eventCounts, lastDevice
    static RID_INPUT := 0x10000003, HEADER_SIZE := 24

    size := 0
    DllCall("GetRawInputData", "Ptr", lParam, "UInt", RID_INPUT,
            "Ptr", 0, "UInt*", &size, "UInt", HEADER_SIZE)
    if !size
        return
    buf := Buffer(size, 0)
    if !DllCall("GetRawInputData", "Ptr", lParam, "UInt", RID_INPUT,
                "Ptr", buf, "UInt*", &size, "UInt", HEADER_SIZE)
        return

    hDevice     := NumGet(buf, 8, "Ptr")                    ; RAWINPUTHEADER.hDevice
    buttonFlags := NumGet(buf, HEADER_SIZE + 4, "UShort")   ; RAWMOUSE.usButtonFlags
    delta       := NumGet(buf, HEADER_SIZE + 6, "Short")    ; RAWMOUSE.usButtonData

    if (buttonFlags & 0x0400)
        axis := "vertical wheel"
    else if (buttonFlags & 0x0800)
        axis := "horizontal wheel"
    else
        return  ; movement/clicks: ignored

    key := Format("0x{:X}", hDevice)
    eventCounts[key] := eventCounts.Has(key) ? eventCounts[key] + 1 : 1

    ToolTip key "`n" axis "  delta=" delta "`n" eventCounts[key] " events"
                . "`n" GetDeviceName(hDevice)
    SetTimer(ClearTooltip, -2500)

    ; one line per device change, to keep the log readable
    if (hDevice != lastDevice) {
        lastDevice := hDevice
        WriteLog(key "  " axis "  " GetDeviceName(hDevice))
    }
}


ListDevices() {
    n := 0
    DllCall("GetRawInputDeviceList", "Ptr", 0, "UInt*", &n, "UInt", 16)
    if !n
        return
    devList := Buffer(n * 16, 0)
    DllCall("GetRawInputDeviceList", "Ptr", devList, "UInt*", &n, "UInt", 16)
    typeNames := ["mouse", "keyboard", "hid"]
    Loop n {
        base := (A_Index - 1) * 16
        h := NumGet(devList, base, "Ptr")
        t := NumGet(devList, base + 8, "UInt")
        WriteLog("  " Format("0x{:X}", h) "  " (typeNames.Has(t + 1) ? typeNames[t + 1] : t)
                 . "  " GetDeviceName(h))
    }
}


GetDeviceName(hDevice) {
    static cache := Map()
    if cache.Has(hDevice)
        return cache[hDevice]
    size := 0
    DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice, "UInt", 0x20000007,
            "Ptr", 0, "UInt*", &size)
    name := "?"
    if size {
        buf := Buffer(size * 2 + 2, 0)
        if DllCall("GetRawInputDeviceInfoW", "Ptr", hDevice, "UInt", 0x20000007,
                   "Ptr", buf, "UInt*", &size) != -1
            name := StrGet(buf, "UTF-16")
    }
    return cache[hDevice] := name
}


ClearTooltip() {
    ToolTip
}

WriteLog(msg) {
    try FileAppend msg "`n", A_ScriptDir "\_device-probe.log", "UTF-8"
}
