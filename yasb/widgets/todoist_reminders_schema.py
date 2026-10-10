from pydantic import Field

from core.validation.widgets.base_model import CallbacksConfig, CustomBaseModel


class TodoistRemindersCallbacksConfig(CallbacksConfig):
    on_left: str = "show_card"


class TodoistRemindersConfig(CustomBaseModel):
    class_name: str = ""
    # {task}: the next task with a time today; {when}: "in 12 min", "now", "5 min late"
    label: str = "{task} · {when}"
    label_max_length: int = Field(default=32, ge=4)
    # Tasks fetched with this Todoist filter
    query: str = "today | overdue"
    # A file holding just the token (the one Neovim's Todoist uses); the
    # TODOIST_API_TOKEN environment variable wins when set
    token_file: str = "%LOCALAPPDATA%\\nvim-data\\todoist_token"
    poll_interval: int = Field(default=30, ge=15)
    # Show the label this long before a task's time (minutes); 0 = always
    lookahead: int = Field(default=0, ge=0)
    snooze_minutes: int = Field(default=10, ge=1)
    # A .wav played when a card opens on its own; "" = silent
    sound: str = "C:\\Windows\\Media\\Windows Notify Calendar.wav"
    callbacks: TodoistRemindersCallbacksConfig = TodoistRemindersCallbacksConfig()
