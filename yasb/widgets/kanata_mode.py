"""The current kanata layer as a short label (a vim-like mode letter).

kanata's TCP server (kanata --port) sends {"LayerChange":{"new":"<layer>"}}
on connect and on every layer change; a reader thread listens and the label
changes at once, no polling. If kanata is not running or restarts, the thread
reconnects on its own.
"""

import json
import logging
import socket
import threading

from PyQt6.QtCore import QObject, pyqtSignal

from core.validation.widgets.yasb.kanata_mode import KanataModeConfig
from core.widgets.base import BaseWidget


class KanataListener(QObject):
    layer_changed = pyqtSignal(str)
    connection_changed = pyqtSignal(bool)

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
                if isinstance(message, dict) and "LayerChange" in message:
                    layer = message["LayerChange"].get("new")
                    if isinstance(layer, str):
                        self._emit(self.layer_changed, layer)


class KanataModeWidget(BaseWidget):
    validation_schema = KanataModeConfig

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
        self.destroyed.connect(self._listener.stop)
        self._listener.start()

    def _on_connection_changed(self, connected: bool):
        logging.debug("kanata_mode: %s", "connected" if connected else "disconnected")
        if self.config.hide_offline:
            self.setVisible(connected and bool(self._mode))

    def _on_layer_changed(self, layer: str):
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
