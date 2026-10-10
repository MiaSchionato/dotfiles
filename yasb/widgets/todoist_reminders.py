"""The next Todoist task with a time today, in the bar, and a quiet card when
its time comes.

Tasks are fetched from Todoist's API v1 every poll_interval seconds (a filter
query, "today | overdue" by default). The label shows the next task with a
time and how long until it. When a task's time comes, a small card opens
under the bar and stays until it is answered: Done (completes the task in
Todoist), Snooze (asks again in snooze_minutes) or Close (until the next
time). A left click on the label opens the card for the next task.
"""

import json
import logging
import os
import threading
import urllib.parse
import urllib.request
import winsound
from datetime import datetime, timedelta

from PyQt6.QtCore import QObject, QPoint, Qt, QTimer, pyqtSignal
from PyQt6.QtWidgets import QHBoxLayout, QLabel, QPushButton, QVBoxLayout, QWidget

from core.validation.widgets.yasb.todoist_reminders import TodoistRemindersConfig
from core.widgets.base import BaseWidget

API = "https://api.todoist.com/api/v1"


def _read_token(token_file: str) -> str | None:
    token = os.environ.get("TODOIST_API_TOKEN")
    if token:
        return token.strip()
    try:
        with open(os.path.expandvars(token_file), encoding="utf-8") as f:
            return f.read().strip() or None
    except OSError:
        return None


def _request(token: str, path: str, method: str = "GET") -> dict | None:
    request = urllib.request.Request(
        API + path, method=method, headers={"Authorization": f"Bearer {token}"}
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        body = response.read()
    return json.loads(body) if body else None


def _due_time(task: dict) -> datetime | None:
    """The task's time, local and naive; None for a task with only a date."""
    due = task.get("due") or {}
    value = due.get("datetime") or due.get("date") or ""
    if "T" not in value:
        return None
    try:
        moment = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if moment.tzinfo:
        moment = moment.astimezone().replace(tzinfo=None)
    return moment


class TodoistClient(QObject):
    tasks_ready = pyqtSignal(list)

    def __init__(self, token_file: str, query: str):
        super().__init__()
        self._token_file = token_file
        self._query = query

    def fetch(self):
        threading.Thread(target=self._fetch, daemon=True).start()

    def close_task(self, task_id: str):
        threading.Thread(target=self._close, args=(task_id,), daemon=True).start()

    def _emit(self, tasks: list):
        try:
            self.tasks_ready.emit(tasks)
        except RuntimeError:
            pass

    def _fetch(self):
        token = _read_token(self._token_file)
        if not token:
            logging.warning("todoist_reminders: no token")
            return
        tasks, cursor = [], None
        try:
            while True:
                path = "/tasks/filter?query=" + urllib.parse.quote(self._query)
                if cursor:
                    path += "&cursor=" + urllib.parse.quote(cursor)
                page = _request(token, path) or {}
                tasks += page.get("results", [])
                cursor = page.get("next_cursor")
                if not cursor:
                    break
        except Exception as e:
            logging.warning("todoist_reminders: fetch failed: %s", e)
            return
        self._emit(tasks)

    def _close(self, task_id: str):
        token = _read_token(self._token_file)
        if not token:
            return
        try:
            _request(token, f"/tasks/{task_id}/close", method="POST")
        except Exception as e:
            logging.warning("todoist_reminders: close failed: %s", e)
        self._fetch()


class ReminderCard(QWidget):
    """A small card under the bar: the task, Done, Snooze, Close."""

    answered = pyqtSignal(str, str)  # task id, "done" | "snooze" | "close"

    def __init__(self, snooze_minutes: int):
        super().__init__()
        self._task_id = ""
        self.setWindowFlags(
            Qt.WindowType.FramelessWindowHint
            | Qt.WindowType.WindowStaysOnTopHint
            | Qt.WindowType.Tool
            | Qt.WindowType.WindowDoesNotAcceptFocus
        )
        self.setAttribute(Qt.WidgetAttribute.WA_ShowWithoutActivating)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)

        frame = QWidget(self)
        frame.setObjectName("card")
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.addWidget(frame)

        self._title = QLabel()
        self._title.setWordWrap(True)
        self._title.setObjectName("title")
        self._when = QLabel()
        self._when.setObjectName("when")
        buttons = QHBoxLayout()
        buttons.setSpacing(6)
        for text, answer in (("Done", "done"), (f"+{snooze_minutes} min", "snooze"), ("Close", "close")):
            button = QPushButton(text)
            button.setCursor(Qt.CursorShape.PointingHandCursor)
            button.clicked.connect(lambda _=False, a=answer: self._answer(a))
            buttons.addWidget(button)

        layout = QVBoxLayout(frame)
        layout.setContentsMargins(12, 10, 12, 10)
        layout.setSpacing(6)
        layout.addWidget(self._title)
        layout.addWidget(self._when)
        layout.addLayout(buttons)

        self.setStyleSheet("""
            #card { background-color: #011627; border: 1px solid #3a86ff; border-radius: 8px; }
            #title { color: #c3ccdc; font-size: 13px; font-weight: bold; }
            #when { color: #82aaff; font-size: 11px; }
            QPushButton { background-color: #0e293f; color: #c3ccdc; border: none;
                          border-radius: 5px; padding: 4px 10px; font-size: 11px; }
            QPushButton:hover { background-color: #1d3b53; }
        """)
        self.setFixedWidth(280)

    def show_task(self, task: dict, when: str, anchor: QPoint):
        self._task_id = task["id"]
        self._title.setText(task.get("content", ""))
        self._when.setText(when)
        self.adjustSize()
        self.move(anchor.x() - self.width(), anchor.y())
        self.show()
        self.raise_()

    def task_id(self) -> str:
        return self._task_id if self.isVisible() else ""

    def _answer(self, answer: str):
        self.hide()
        self.answered.emit(self._task_id, answer)


class TodoistRemindersWidget(BaseWidget):
    validation_schema = TodoistRemindersConfig
    # One bar per monitor: only the first widget opens cards
    _card_owner: "TodoistRemindersWidget | None" = None

    def __init__(self, config: TodoistRemindersConfig):
        super().__init__(class_name=f"todoist-reminders-widget {config.class_name}".strip())
        self.config = config
        self._tasks: list[dict] = []
        self._snoozed: dict[str, datetime] = {}  # task id -> ask again after
        self._answered: set[tuple[str, str]] = set()  # (task id, due) closed or done
        self._next: dict | None = None

        self._init_container()
        self.build_widget_label(self.config.label)
        self.register_callback("show_card", self._show_next_card)
        self.callback_left = self.config.callbacks.on_left
        self.callback_right = self.config.callbacks.on_right
        self.callback_middle = self.config.callbacks.on_middle
        self.setVisible(False)

        self._card = None
        if TodoistRemindersWidget._card_owner is None:
            TodoistRemindersWidget._card_owner = self
            self._card = ReminderCard(self.config.snooze_minutes)
            self._card.answered.connect(self._on_answered)
            self.destroyed.connect(TodoistRemindersWidget._release_card)

        self._client = TodoistClient(self.config.token_file, self.config.query)
        self._client.tasks_ready.connect(self._on_tasks)
        self._client.fetch()

        self._poll = QTimer(self)
        self._poll.timeout.connect(self._client.fetch)
        self._poll.start(self.config.poll_interval * 1000)
        self._tick = QTimer(self)
        self._tick.timeout.connect(self._refresh)
        self._tick.start(15000)

    @staticmethod
    def _release_card():
        TodoistRemindersWidget._card_owner = None

    def _on_tasks(self, tasks: list):
        self._tasks = tasks
        self._refresh()

    def _timed(self) -> list[tuple[datetime, dict]]:
        timed = [(_due_time(t), t) for t in self._tasks]
        return sorted(((d, t) for d, t in timed if d), key=lambda pair: pair[0])

    @staticmethod
    def _when(due: datetime, now: datetime) -> str:
        minutes = round((due - now).total_seconds() / 60)
        if minutes > 59:
            return f"at {due:%H:%M}"
        if minutes > 0:
            return f"in {minutes} min"
        if minutes == 0:
            return "now"
        late = -minutes
        return f"{late} min late" if late < 60 else f"{late // 60} h late"

    def _refresh(self):
        now = datetime.now()
        timed = [(d, t) for d, t in self._timed() if (t["id"], t["due"].get("date")) not in self._answered]
        # The label: the earliest one still open (an overdue one first)
        self._next = timed[0] if timed else None
        visible = bool(self._next)
        if self._next and self.config.lookahead:
            visible = self._next[0] - now <= timedelta(minutes=self.config.lookahead)
        if self._next:
            due, task = self._next
            # Too long: the task name gives way, the time stays whole
            when = self._when(due, now)
            name = task.get("content", "")
            room = self.config.label_max_length - len(self.config.label.format(task="", when=when))
            if len(name) > room:
                name = name[: max(room - 1, 1)] + "…"
            text = self.config.label.format(task=name, when=when)
            for widget in self._widgets:
                widget.setText(text)
                widget.setProperty("class", "label due" if due <= now else "label")
                widget.style().unpolish(widget)
                widget.style().polish(widget)
        self.setVisible(visible)

        # The card: the first task whose time has come, unless snoozed
        if self._card and not self._card.task_id():
            for due, task in timed:
                if due > now:
                    break
                if self._snoozed.get(task["id"], now) > now:
                    continue
                self._open_card(task, due, now)
                self._play_sound()
                break

    def _play_sound(self):
        if self.config.sound:
            try:
                winsound.PlaySound(
                    os.path.expandvars(self.config.sound), winsound.SND_FILENAME | winsound.SND_ASYNC
                )
            except RuntimeError as e:
                logging.warning("todoist_reminders: no sound: %s", e)

    def _anchor(self) -> QPoint:
        point = self.mapToGlobal(QPoint(self.width(), self.height()))
        return QPoint(point.x(), point.y() + 6)

    def _open_card(self, task: dict, due: datetime, now: datetime):
        owner = self._card or (TodoistRemindersWidget._card_owner and TodoistRemindersWidget._card_owner._card)
        if owner:
            logging.info("todoist_reminders: card for %s (%s)", task["id"], due)
            owner.show_task(task, self._when(due, now), self._anchor())

    def _show_next_card(self):
        if self._next:
            due, task = self._next
            self._open_card(task, due, datetime.now())

    def _on_answered(self, task_id: str, answer: str):
        task = next((t for t in self._tasks if t["id"] == task_id), None)
        if not task:
            return
        logging.info("todoist_reminders: %s %s", answer, task_id)
        if answer == "snooze":
            self._snoozed[task_id] = datetime.now() + timedelta(minutes=self.config.snooze_minutes)
        elif answer == "done":
            self._answered.add((task_id, task["due"].get("date")))
            self._client.close_task(task_id)
        elif (_due_time(task) or datetime.max) <= datetime.now():
            # Close: done asking for this time (a task not due yet stays)
            self._answered.add((task_id, task["due"].get("date")))
        self._refresh()
