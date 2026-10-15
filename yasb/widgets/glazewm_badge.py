"""The GlazeWM workspace as one letter in a round badge.

Same look as the vim mode badge (kanata_mode.py): a small round label with the
first letter of the workspace's name ("Nvim" -> N). Each bar shows the workspace
displayed on its own monitor; the one with the keyboard focus also has the
"focused" class, so the stylesheet can paint the others dimmer (or, with
show_unfocused off, they hide).
"""

import logging

from PyQt6.QtCore import QObject, pyqtSlot
from PyQt6.QtGui import QShowEvent
from PyQt6.QtWidgets import QLabel, QWidget

from core.utils.utilities import refresh_widget_style
from core.utils.win32.utils import get_monitor_hwnd
from core.validation.widgets.yasb.glazewm_badge import GlazewmBadgeConfig
from core.widgets.base import BaseWidget
from core.widgets.services.glazewm.client import GlazewmClient, Monitor


class GlazewmBadgeWidget(BaseWidget):
    validation_schema = GlazewmBadgeConfig

    def __init__(self, config: GlazewmBadgeConfig):
        super().__init__(class_name=f"glazewm-badge {config.class_name}".strip())
        self.config = config
        self.monitor_handle: int | None = None
        self._focused = False

        self._label = QLabel("", self)
        self._label.setProperty("class", "label")
        self.widget_layout.addWidget(self._label)
        # The widget itself stays shown (its showEvent connects to GlazeWM); only
        # the label hides.
        self._label.setVisible(False)

        self._client = GlazewmClient(
            self.config.glazewm_server_uri,
            [
                "sub -e workspace_activated workspace_deactivated workspace_updated focus_changed focused_container_moved",
                "query monitors",
            ],
        )
        self._client.glazewm_connection_status.connect(self._on_connection)  # type: ignore
        self._client.workspaces_data_processed.connect(self._on_monitors)  # type: ignore

    def showEvent(self, a0: QShowEvent | None):
        super().showEvent(a0)
        self.monitor_handle = get_monitor_hwnd(int(QWidget.winId(self)))
        self._client.connect()

    @pyqtSlot(bool)
    def _on_connection(self, connected: bool):
        logging.debug("glazewm_badge: %s", "connected" if connected else "disconnected")
        if not connected:
            self._label.setVisible(False)

    @pyqtSlot(list)
    def _on_monitors(self, monitors: list[Monitor]):
        mine = next((m for m in monitors if m.hwnd == self.monitor_handle), None)
        if not mine:
            return
        shown = next((w for w in mine.workspaces if w.is_displayed), None)
        if shown is None:
            self._label.setVisible(False)
            return
        focused = shown.focus
        name = shown.display_name or shown.name
        self._label.setText(self.config.labels.get(shown.name) or self._initial(name))
        if focused != self._focused or not self._label.property("state"):
            self._focused = focused
            self._label.setProperty("class", "label focused" if focused else "label")
            self._label.setProperty("state", "on")
            refresh_widget_style(self._label)
        self._label.setVisible(focused or self.config.show_unfocused)

    @staticmethod
    def _initial(name: str) -> str:
        for char in name:
            if char.isalnum():
                return char.upper()
        return "?"
