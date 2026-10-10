"""Vimium-like window hints: a letter over each window of the focused monitor.

The windows come from komorebi (`komorebic state`): the visible window of each
container of the focused workspace, the monocle and maximized ones, and the
floating ones. Badges are placed in physical pixels with SetWindowPos, so the
monitor's scaling does not move them.
"""

import ctypes
import json
import logging
import subprocess
from ctypes import wintypes

from PyQt6.QtCore import Qt, QTimer
from PyQt6.QtWidgets import QHBoxLayout, QLabel, QWidget

# Own handles, so these argtypes do not clash with yasb's bindings
user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
user32.SetWindowPos.argtypes = [
    wintypes.HWND, wintypes.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wintypes.UINT
]
user32.GetWindowRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
user32.GetForegroundWindow.restype = wintypes.HWND
user32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.c_void_p]
for name in ("IsWindowVisible", "IsIconic", "BringWindowToTop", "SetForegroundWindow"):
    getattr(user32, name).argtypes = [wintypes.HWND]
user32.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
user32.MonitorFromWindow.argtypes = [wintypes.HWND, wintypes.DWORD]
user32.MonitorFromWindow.restype = wintypes.HMONITOR
user32.GetDpiForWindow.argtypes = [wintypes.HWND]


class MONITORINFO(ctypes.Structure):
    _fields_ = [("cbSize", wintypes.DWORD), ("rcMonitor", wintypes.RECT),
                ("rcWork", wintypes.RECT), ("dwFlags", wintypes.DWORD)]


user32.GetMonitorInfoW.argtypes = [wintypes.HMONITOR, ctypes.POINTER(MONITORINFO)]

HWND_TOPMOST = -1
SWP_NOSIZE = 0x0001
SWP_NOACTIVATE = 0x0010
SWP_SHOWWINDOW = 0x0040
SW_RESTORE = 9
MONITOR_DEFAULTTONEAREST = 2


def font_size_for(hwnd: int, ratio: float) -> int:
    """A font size (Qt's logical pixels) that is ratio of the height of the
    window's monitor: the same look on every monitor, whatever its scaling."""
    info = MONITORINFO(cbSize=ctypes.sizeof(MONITORINFO))
    user32.GetMonitorInfoW(user32.MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), ctypes.byref(info))
    height = info.rcMonitor.bottom - info.rcMonitor.top
    scale = (user32.GetDpiForWindow(hwnd) or 96) / 96
    return max(8, round(height * ratio / scale))


def _komorebi_state() -> dict | None:
    try:
        output = subprocess.run(
            ["komorebic-no-console.exe", "state"],
            capture_output=True,
            timeout=2,
            creationflags=subprocess.CREATE_NO_WINDOW,
        ).stdout
        return json.loads(output)
    except (OSError, ValueError, subprocess.SubprocessError) as e:
        logging.warning("kanata hints: no komorebi state: %s", e)
        return None


def _windows(container: dict | None, visible_only: bool) -> list[dict]:
    if not container:
        return []
    windows = container.get("windows", {})
    elements = windows.get("elements", [])
    if visible_only and elements:
        return [elements[min(windows.get("focused", 0), len(elements) - 1)]]
    return elements


def focused_monitor_windows() -> list[int]:
    """The hwnds to hint, left to right, then top to bottom."""
    state = _komorebi_state()
    if not state:
        return []
    monitors = state["monitors"]
    monitor = monitors["elements"][monitors["focused"]]
    workspaces = monitor["workspaces"]
    workspace = workspaces["elements"][workspaces["focused"]]

    found: list[dict] = []
    for container in workspace.get("containers", {}).get("elements", []):
        found += _windows(container, visible_only=True)
    found += _windows(workspace.get("monocle_container"), visible_only=True)
    if workspace.get("maximized_window"):
        found.append(workspace["maximized_window"])
    floating = workspace.get("floating_windows") or []
    found += floating.get("elements", []) if isinstance(floating, dict) else floating

    hwnds = []
    for window in found:
        hwnd = window.get("hwnd")
        if hwnd and hwnd not in hwnds and user32.IsWindowVisible(hwnd) and not user32.IsIconic(hwnd):
            hwnds.append(hwnd)

    def center(hwnd):
        rect = wintypes.RECT()
        user32.GetWindowRect(hwnd, ctypes.byref(rect))
        return ((rect.left + rect.right) // 2, (rect.top + rect.bottom) // 2)

    return sorted(hwnds, key=lambda h: center(h))


def focus_window(hwnd: int):
    """SetForegroundWindow from a process in the background: attach to the
    thread of the window in front first, or Windows refuses."""
    foreground = user32.GetForegroundWindow()
    fg_thread = user32.GetWindowThreadProcessId(foreground, None)
    own_thread = kernel32.GetCurrentThreadId()
    attached = fg_thread != own_thread and user32.AttachThreadInput(own_thread, fg_thread, True)
    try:
        if user32.IsIconic(hwnd):
            user32.ShowWindow(hwnd, SW_RESTORE)
        user32.BringWindowToTop(hwnd)
        user32.SetForegroundWindow(hwnd)
    finally:
        if attached:
            user32.AttachThreadInput(own_thread, fg_thread, False)


class WindowHints:
    """The badges: one small top-most window per hinted window."""

    def __init__(self, keys: list[str], style: str, size: float):
        self._keys = keys
        self._style = style
        self._size = size
        self._badges: list[QWidget] = []
        self.targets: list[int] = []

    def show(self):
        self.hide()
        self.targets = focused_monitor_windows()[: len(self._keys)]
        for key, hwnd in zip(self._keys, self.targets):
            rect = wintypes.RECT()
            user32.GetWindowRect(hwnd, ctypes.byref(rect))
            # A see-through window with the styled label inside: on the window
            # itself, the transparency would also drop the label's background
            badge = QWidget()
            layout = QHBoxLayout(badge)
            layout.setContentsMargins(0, 0, 0, 0)
            label = QLabel(key.upper())
            font = font_size_for(hwnd, self._size)
            label.setStyleSheet(
                f"{self._style} font-size: {font}px; padding: {font // 6}px {font // 3}px;"
                f"border-radius: {font // 3}px;"
            )
            label.setAlignment(Qt.AlignmentFlag.AlignCenter)
            layout.addWidget(label)
            badge.setWindowFlags(
                Qt.WindowType.FramelessWindowHint
                | Qt.WindowType.WindowStaysOnTopHint
                | Qt.WindowType.Tool
                | Qt.WindowType.WindowDoesNotAcceptFocus
            )
            badge.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
            badge.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
            badge.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents)
            badge.show()
            self._badges.append(badge)
            # Qt moves the window once more after show: place it after that
            QTimer.singleShot(0, lambda b=badge, r=rect: self._place(b, r))

    def _place(self, badge: QWidget, rect: wintypes.RECT):
        if badge not in self._badges:
            return
        badge_hwnd = int(badge.winId())
        size = wintypes.RECT()
        user32.GetWindowRect(badge_hwnd, ctypes.byref(size))
        width, height = size.right - size.left, size.bottom - size.top
        x = (rect.left + rect.right - width) // 2
        y = (rect.top + rect.bottom - height) // 2
        user32.SetWindowPos(badge_hwnd, HWND_TOPMOST, x, y, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW)

    def hide(self):
        for badge in self._badges:
            badge.hide()
            badge.deleteLater()
        self._badges = []

    def pick(self, index: int):
        if 0 <= index < len(self.targets):
            focus_window(self.targets[index])
            logging.info(
                "kanata hints: picked %s, foreground now %s", self.targets[index], user32.GetForegroundWindow()
            )
        else:
            logging.info("kanata hints: no window %s of %s", index, self.targets)
