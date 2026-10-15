; =============================================================
;  GlazeWM's own socket from AutoHotkey, no CLI process and no helper script
;
;  GlazeWM speaks WebSocket on ws://127.0.0.1:6123 and takes the same text the
;  CLI sends ("command --id <id> set-floating", "query monitors"). Windows has a
;  WebSocket client in WinHTTP; this wraps it:
;
;    Glaze.Send("command --id " id " close")      fire and forget
;    json := Glaze.Ask("query windows")           send, wait for its answer
;
;  One connection, kept open; it reconnects once on its own when a call fails
;  (GlazeWM restarted). Every call is guarded: failing returns "" and never stops
;  the script. Calls block the script's thread (a millisecond or two; at most
;  RECEIVE_TIMEOUT_MS if GlazeWM hangs).
; =============================================================

class Glaze {
    static HOST := "127.0.0.1"
    static PORT := 6123
    static RECEIVE_TIMEOUT_MS := 2000
    static session := 0
    static conn := 0
    static ws := 0
    static BUFFER_SIZE := 262144            ; `query monitors` can be big

    ; Opens the connection if there is none. True when connected.
    static Connect() {
        if Glaze.ws
            return true
        try {
            h := DllCall("winhttp\WinHttpOpen", "Str", "windows.ahk", "UInt", 1, "Ptr", 0, "Ptr", 0, "UInt", 0, "Ptr")
            if !h
                return false
            Glaze.session := h
            DllCall("winhttp\WinHttpSetTimeouts", "Ptr", h, "Int", 1000, "Int", 1000, "Int", 1000, "Int", Glaze.RECEIVE_TIMEOUT_MS)
            conn := DllCall("winhttp\WinHttpConnect", "Ptr", h, "Str", Glaze.HOST, "UShort", Glaze.PORT, "UInt", 0, "Ptr")
            req := conn ? DllCall("winhttp\WinHttpOpenRequest", "Ptr", conn, "Str", "GET", "Str", "/", "Ptr", 0, "Ptr", 0, "Ptr", 0, "UInt", 0, "Ptr") : 0
            ok := req
                && DllCall("winhttp\WinHttpSetOption", "Ptr", req, "UInt", 114, "Ptr", 0, "UInt", 0)      ; upgrade to WebSocket
                && DllCall("winhttp\WinHttpSendRequest", "Ptr", req, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt", 0, "UInt", 0, "UPtr", 0)
                && DllCall("winhttp\WinHttpReceiveResponse", "Ptr", req, "Ptr", 0)
            ws := ok ? DllCall("winhttp\WinHttpWebSocketCompleteUpgrade", "Ptr", req, "Ptr", 0, "Ptr") : 0
            if req
                DllCall("winhttp\WinHttpCloseHandle", "Ptr", req)
            Glaze.conn := conn              ; kept: it must outlive the socket
            if !ws {
                Glaze.Close()
                return false
            }
            Glaze.ws := ws
            return true
        } catch {
            Glaze.Close()
            return false
        }
    }

    static Close() {
        if Glaze.ws {
            try DllCall("winhttp\WinHttpWebSocketClose", "Ptr", Glaze.ws, "UShort", 1000, "Ptr", 0, "UInt", 0)
            try DllCall("winhttp\WinHttpCloseHandle", "Ptr", Glaze.ws)
        }
        if Glaze.conn
            try DllCall("winhttp\WinHttpCloseHandle", "Ptr", Glaze.conn)
        if Glaze.session
            try DllCall("winhttp\WinHttpCloseHandle", "Ptr", Glaze.session)
        Glaze.ws := 0
        Glaze.conn := 0
        Glaze.session := 0
    }

    ; Sends one text message. True when it went out.
    static Send(text) {
        if !Glaze.Connect()
            return false
        try {
            size := StrPut(text, "UTF-8") - 1
            buf := Buffer(size)
            StrPut(text, buf, "UTF-8")
            if DllCall("winhttp\WinHttpWebSocketSend", "Ptr", Glaze.ws, "UInt", 2, "Ptr", buf, "UInt", size, "UInt") = 0
                return true
        }
        Glaze.Close()                       ; stale socket: reconnect once, on the next try
        return false
    }

    ; The next whole text message, or "" (timeout / closed).
    static Receive() {
        if !Glaze.ws
            return ""
        text := ""
        buf := Buffer(Glaze.BUFFER_SIZE)
        loop {
            read := 0, kind := 0
            if DllCall("winhttp\WinHttpWebSocketReceive", "Ptr", Glaze.ws, "Ptr", buf, "UInt", buf.Size, "UInt*", &read, "UInt*", &kind, "UInt") != 0 {
                Glaze.Close()
                return ""
            }
            if (kind = 4) {                 ; close frame
                Glaze.Close()
                return ""
            }
            text .= StrGet(buf, read, "UTF-8")
            if (kind != 3 && kind != 1)     ; 3 / 1: a fragment, more follows
                return text
        }
    }

    ; Sends `text`, then reads until the message that answers it (its clientMessage
    ; is the same text); returns that message, or "". Tries again once on a new
    ; connection if the first attempt fails.
    static Ask(text) {
        loop 2 {
            if Glaze.Send(text) {
                needle := '"clientMessage":"' text '"'
                loop 20 {
                    reply := Glaze.Receive()
                    if (reply = "")
                        break
                    if InStr(reply, needle)
                        return reply
                }
            }
            Glaze.Close()
        }
        return ""
    }
}
