"""kanata's base layer by the app in focus (what komokana did).

On every foreground change (a Windows event, so Win+Tab counts too) the exe of
the focused window picks a base layer; kanata gets ChangeLayer only when that
layer changes. If kanata reports a different base layer (a config reload
resets it to the first one), the right one is sent again.
"""

import ctypes
from ctypes import wintypes

user32 = ctypes.WinDLL("user32")
kernel32 = ctypes.WinDLL("kernel32")
user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
kernel32.OpenProcess.restype = wintypes.HANDLE
kernel32.QueryFullProcessImageNameW.argtypes = [
    wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)
]
kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000


def exe_name(hwnd: int) -> str:
    pid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid.value)
    if not handle:
        return ""
    try:
        size = wintypes.DWORD(1024)
        path = ctypes.create_unicode_buffer(size.value)
        if not kernel32.QueryFullProcessImageNameW(handle, 0, path, ctypes.byref(size)):
            return ""
        return path.value.rsplit("\\", 1)[-1].lower()
    finally:
        kernel32.CloseHandle(handle)


class AppLayers:
    def __init__(self, app_layers: dict[str, str], default: str, send):
        self._layers = {exe.lower(): layer for exe, layer in app_layers.items()}
        self._default = default
        self._bases = set(self._layers.values()) | {default}
        self._send = send  # send(layer): ChangeLayer to kanata
        self._target = default

    def on_focus(self, hwnd: int):
        exe = exe_name(hwnd)
        if not exe:
            return
        target = self._layers.get(exe, self._default)
        if target != self._target:
            self._target = target
            self._send(target)

    def on_layer(self, layer: str):
        # A base layer other than ours: kanata lost it (reload, restart)
        if layer in self._bases and layer != self._target:
            self._send(self._target)

    def on_connect(self):
        self._send(self._target)
