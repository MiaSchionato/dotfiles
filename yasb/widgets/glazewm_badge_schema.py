from core.validation.widgets.base_model import CustomBaseModel


class GlazewmBadgeConfig(CustomBaseModel):
    class_name: str = ""
    glazewm_server_uri: str = "ws://localhost:6123"
    # False: only the bar of the monitor you are working on shows its letter
    show_unfocused: bool = True
