from pydantic import Field

from core.validation.widgets.base_model import CallbacksConfig, CustomBaseModel

DEFAULT_MODES = {
    "base": "I",
    "premiere": "I",
    "zen": "I",
    "window": "W",
    "goto": "G",
    "move": "M",
    "resize": "R",
    "cmdline": ":",
}


class KanataModeCallbacksConfig(CallbacksConfig):
    on_left: str = "toggle_label"


class KanataModeConfig(CustomBaseModel):
    class_name: str = ""
    label: str = "{mode}"
    label_alt: str = "{mode}"
    host: str = "127.0.0.1"
    port: int = Field(default=9999, ge=1, le=65535)
    # Layer name -> text shown. A layer missing here (a momentary one: CapsLock,
    # the accents, Win held) keeps the text of the last one listed.
    modes: dict[str, str] = Field(default_factory=lambda: dict(DEFAULT_MODES))
    reconnect_interval: int = Field(default=2000, ge=100)
    hide_offline: bool = True
    callbacks: KanataModeCallbacksConfig = KanataModeCallbacksConfig()
