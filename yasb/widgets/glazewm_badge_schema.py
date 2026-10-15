from pydantic import Field

from core.validation.widgets.base_model import CustomBaseModel


class GlazewmBadgeConfig(CustomBaseModel):
    class_name: str = ""
    glazewm_server_uri: str = "ws://localhost:6123"
    # False: only the bar of the monitor you are working on shows its letter
    show_unfocused: bool = True
    # The letter of a workspace, by name; the first letter of its name when not listed
    labels: dict[str, str] = Field(default_factory=dict)
