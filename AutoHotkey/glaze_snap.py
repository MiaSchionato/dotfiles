"""Snap a window after a Win + drag, over GlazeWM's own IPC socket.

    glaze_snap.py <hwnd> left|right|top [--dry]

Called by windows.ahk when a drag ends at a screen edge. Over the socket, the
commands go out back to back (no process per command, no wait in between), so the
tile is never seen in the wrong place for a moment:

  top            set-fullscreen
  left / right   set-tiling, then, if the window landed on the wrong side of the
                 other tiles of its monitor, the `move --direction` swaps that put
                 it on the side asked (one per tile it has to pass).

GlazeWM puts a window back in tiling at its old slot (or beside the last focused
tile), not where it was dropped, hence the swaps. Alone on its monitor there is no
side, and a move would only send it to the next monitor: nothing is done then.

Standard library only (a minimal WebSocket client: GlazeWM speaks WebSocket on
ws://127.0.0.1:6123).
"""

import base64
import json
import os
import socket
import struct
import sys
import time

HOST, PORT = "127.0.0.1", 6123


class Socket:
    def __init__(self):
        self.sock = socket.create_connection((HOST, PORT), timeout=3)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall(
            (
                f"GET / HTTP/1.1\r\nHost: {HOST}:{PORT}\r\nUpgrade: websocket\r\n"
                f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
                "Sec-WebSocket-Version: 13\r\n\r\n"
            ).encode()
        )
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = self.sock.recv(1024)
            if not chunk:
                raise ConnectionError("handshake closed")
            head += chunk
        if b" 101 " not in head.split(b"\r\n", 1)[0]:
            raise ConnectionError("handshake refused")
        self.rest = head.split(b"\r\n\r\n", 1)[1]

    def send(self, text):
        data = text.encode()
        mask = os.urandom(4)
        n = len(data)
        if n < 126:
            header = bytes([0x81, 0x80 | n])
        elif n < 65536:
            header = bytes([0x81, 0x80 | 126]) + struct.pack(">H", n)
        else:
            header = bytes([0x81, 0x80 | 127]) + struct.pack(">Q", n)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        self.sock.sendall(header + mask + masked)

    def _read(self, n):
        while len(self.rest) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("closed")
            self.rest += chunk
        out, self.rest = self.rest[:n], self.rest[n:]
        return out

    def receive(self):
        """The next text message (fragments joined)."""
        message = b""
        while True:
            b0, b1 = self._read(2)
            n = b1 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self._read(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", self._read(8))[0]
            payload = self._read(n)
            opcode = b0 & 0x0F
            if opcode == 8:
                raise ConnectionError("closed by server")
            if opcode in (1, 0):
                message += payload
                if b0 & 0x80:
                    return message.decode()

    def ask(self, text):
        """Send a query/command and return the response with that clientMessage."""
        self.send(text)
        while True:
            reply = json.loads(self.receive())
            if reply.get("clientMessage") == text:
                return reply

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def walk(node, monitor=None):
    """(monitor index, window) for every window under the tree, in order."""
    if isinstance(node, dict):
        if node.get("type") == "window":
            yield monitor, node
        for child in node.get("children", []):
            yield from walk(child, monitor)
    elif isinstance(node, list):
        for index, child in enumerate(node):
            yield from walk(child, index)


def tree(sock):
    data = sock.ask("query monitors")["data"]["monitors"]
    return list(walk(data))


def find(windows, handle):
    mine = next(((m, w) for m, w in windows if w.get("handle") == handle), None)
    if not mine:
        return None, []
    monitor, window = mine
    others = [
        w
        for m, w in windows
        if m == monitor
        and w is not window
        and w["state"]["type"] == "tiling"
        and w.get("displayState") == "shown"
    ]
    return window, others


def centre(window):
    return window["x"] + window["width"] / 2


def main():
    handle, kind = int(sys.argv[1]), sys.argv[2]
    dry = "--dry" in sys.argv
    sock = Socket()
    try:
        window, _ = find(tree(sock), handle)
        if not window:
            return 1
        ident = window["id"]
        if dry:
            print("would act on", ident, kind)
            return 0
        time.sleep(0.04)  # GlazeWM takes in where the drag ended
        if kind == "top":
            sock.send(f"command --id {ident} set-fullscreen")
            return 0
        sock.send(f"command --id {ident} set-tiling")
        window, others = find(tree(sock), handle)  # the reply of the query comes after
        if not window:
            return 1
        if kind == "left":
            passes = sum(1 for o in others if centre(o) < centre(window))
        else:
            passes = sum(1 for o in others if centre(o) > centre(window))
        for _ in range(passes):
            sock.send(f"command --id {ident} move --direction {kind}")
        time.sleep(0.05)  # let the last command go through before closing
        return 0
    finally:
        sock.close()


if __name__ == "__main__":
    sys.exit(main())
