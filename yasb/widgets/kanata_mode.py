"""The current kanata layer as a short label (a vim-like mode letter).

kanata's TCP server (kanata --port) sends {"LayerChange":{"new":"<layer>"}}
on connect and on every layer change; a reader thread listens and the label
changes at once, no polling. If kanata is not running or restarts, the thread
reconnects on its own.

With hints set, it also shows Vimium-like window hints: kanata goes to the
hint layer (WINDOW's f), a letter shows over each window of the focused
monitor, and a hint key makes kanata push a message (push-msg) naming it.

With app_layers set, it also picks kanata's base layer by the app in focus
(services/kanata/app_layers.py), in place of komokana.
"""

import json
import logging
import socket
import threading

from PyQt6.QtCore import QObject, pyqtSignal

from core.events.service import EventService
from core.events.win32 import WinEvent
from core.validation.widgets.yasb.kanata_mode import KanataModeConfig
from core.widgets.services.kanata.app_layers import AppLayers
from core.widgets.services.kanata.hints import WindowHints
from core.widgets.base import BaseWidget


class KanataListener(QObject):
    layer_changed = pyqtSignal(str)
    connection_changed = pyqtSignal(bool)
    message_pushed = pyqtSignal(str)

    def __init__(self, host: str, port: int, reconnect_interval: float):
        super().__init__()
        self._host = host
        self._port = port
        self._reconnect_interval = reconnect_interval
        self._stop = threading.Event()
        self._sock: socket.socket | None = None

    def start(self):
        threading.Thread(target=self._run, name="kanata-mode", daemon=True).start()

    def stop(self):
        self._stop.set()
        sock = self._sock
        if sock:
            try:
                sock.close()
            except OSError:
                pass

    def send(self, message: dict):
        sock = self._sock
        if sock:
            try:
                sock.sendall(json.dumps(message).encode() + b"\n")
            except OSError:
                pass

    def _emit(self, signal, value):
        try:
            signal.emit(value)
        except RuntimeError:
            # The widget is gone (bar reloaded)
            self._stop.set()

    def _run(self):
        while not self._stop.is_set():
            try:
                self._sock = socket.create_connection((self._host, self._port), timeout=2)
                self._sock.settimeout(None)
                self._emit(self.connection_changed, True)
                self._read(self._sock)
            except OSError:
                pass
            finally:
                if self._sock:
                    try:
                        self._sock.close()
                    except OSError:
                        pass
                    self._sock = None
            if self._stop.is_set():
                break
            self._emit(self.connection_changed, False)
            self._stop.wait(self._reconnect_interval)

    def _read(self, sock: socket.socket):
        buffer = b""
        while not self._stop.is_set():
            chunk = sock.recv(4096)
            if not chunk:
                return
            buffer += chunk
            while b"\n" in buffer:
                line, buffer = buffer.split(b"\n", 1)
                try:
                    message = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(message, dict):
                    continue
                if "LayerChange" in message:
                    layer = message["LayerChange"].get("new")
                    if isinstance(layer, str):
                        self._emit(self.layer_changed, layer)
                elif "MessagePush" in message:
                    pushed = message["MessagePush"].get("message")
                    if isinstance(pushed, list):
                        pushed = " ".join(str(part) for part in pushed)
                    if isinstance(pushed, str):
                        self._emit(self.message_pushed, pushed)


class KanataModeWidget(BaseWidget):
    validation_schema = KanataModeConfig
    # One bar per monitor, one widget each: only the first shows the hints
    # and picks the app layers
    _owner: "KanataModeWidget | None" = None
    foreground_changed = pyqtSignal(int, WinEvent)

    def __init__(self, config: KanataModeConfig):
        super().__init__(class_name=f"kanata-mode-widget {config.class_name}".strip())
        self.config = config
        self._mode = ""
        self._show_alt_label = False

        self._init_container()
        self.build_widget_label(self.config.label, self.config.label_alt)

        self.register_callback("toggle_label", self._toggle_label)
        self.callback_left = self.config.callbacks.on_left
        self.callback_right = self.config.callbacks.on_right
        self.callback_middle = self.config.callbacks.on_middle

        if self.config.hide_offline:
            self.setVisible(False)

        self._listener = KanataListener(self.config.host, self.config.port, self.config.reconnect_interval / 1000)
        self._listener.layer_changed.connect(self._on_layer_changed)
        self._listener.connection_changed.connect(self._on_connection_changed)
        self._hints = None
        self._app_layers = None
        if KanataModeWidget._owner is None:
            KanataModeWidget._owner = self
            self.destroyed.connect(KanataModeWidget._release_owner)
            if self.config.hints:
                self._hints = WindowHints(self.config.hints.keys, self.config.hints.style, self.config.hints.size)
                self._listener.message_pushed.connect(self._on_message_pushed)
            if self.config.app_layers:
                self._app_layers = AppLayers(
                    self.config.app_layers,
                    self.config.default_layer,
                    lambda layer: self._listener.send({"ChangeLayer": {"new": layer}}),
                )
                self.foreground_changed.connect(lambda hwnd, _: self._app_layers.on_focus(hwnd))
                EventService().register_event(WinEvent.EventSystemForeground, self.foreground_changed)
        self.destroyed.connect(self._listener.stop)
        self._listener.start()

    def _on_connection_changed(self, connected: bool):
        logging.debug("kanata_mode: %s", "connected" if connected else "disconnected")
        if connected and self._app_layers:
            self._app_layers.on_connect()
        if self.config.hide_offline:
            self.setVisible(connected and bool(self._mode))

    @staticmethod
    def _release_owner():
        KanataModeWidget._owner = None

    def _on_message_pushed(self, message: str):
        logging.info("kanata_mode: pushed %r", message)
        message = message.strip().strip('"')
        prefix = self.config.hints.message_prefix
        if message.startswith(prefix):
            try:
                index = int(message[len(prefix) :])
            except ValueError:
                return
            self._hints.hide()
            self._hints.pick(index)

    def _on_layer_changed(self, layer: str):
        if self._app_layers:
            self._app_layers.on_layer(layer)
        if self._hints:
            if layer == self.config.hints.layer:
                self._hints.show()
            else:
                self._hints.hide()
        mode = self.config.modes.get(layer)
        if mode is None:
            # A momentary layer: keep the last mode
            return
        self._mode = mode
        self._update_label()
        self.setVisible(True)

    def _toggle_label(self):
        self._show_alt_label = not self._show_alt_label
        for widget in self._widgets:
            widget.setVisible(not self._show_alt_label)
        for widget in self._widgets_alt:
            widget.setVisible(self._show_alt_label)
        self._update_label()

    def _update_label(self):
        widgets = self._widgets_alt if self._show_alt_label else self._widgets
        content = self.config.label_alt if self._show_alt_label else self.config.label
        for widget in widgets:
            widget.setText(content.format(mode=self._mode))
