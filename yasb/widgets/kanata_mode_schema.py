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
    "hint": "F",
}

DEFAULT_HINT_STYLE = (
    "background-color: #82aaff; color: #092236; font-weight: bold;"
)


class KanataHintsConfig(CustomBaseModel):
    # The layer kanata is in while the hints are up (WINDOW's f)
    layer: str = "hint"
    # Pushed by kanata (push-msg) when a hint key is pressed: the prefix, then
    # the index of the key in keys ("hint 0" for the first)
    message_prefix: str = "hint "
    keys: list[str] = Field(default_factory=lambda: ["a", "s", "d", "f", "j", "k", "l", ";"])
    # Colors etc.; the size comes from size
    style: str = DEFAULT_HINT_STYLE
    # Letter height as a share of the monitor's height
    size: float = Field(default=0.009, gt=0, lt=0.2)


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
    # Base layer by the exe in focus (what komokana did); empty = off
    app_layers: dict[str, str] = {}
    default_layer: str = "base"
    # Vimium-like window hints; off when missing
    hints: KanataHintsConfig | None = None
    callbacks: KanataModeCallbacksConfig = KanataModeCallbacksConfig()
