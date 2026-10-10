# yasb widgets of my own

yasb only loads widgets from its source tree, so yasb runs from a clone
(`~/.config/yasb-src`, tag v2.0.7 plus the local branch `kanata-mode`, in a
Python 3.14 venv; the Desktop stack task starts it). These are copies of what
that branch adds:

| Here | In yasb-src/src/core/ |
|---|---|
| `kanata_mode.py` | `widgets/yasb/kanata_mode.py` |
| `kanata_mode_schema.py` | `validation/widgets/yasb/kanata_mode.py` |
| `kanata_hints.py` | `widgets/services/kanata/hints.py` |
| `kanata_app_layers.py` | `widgets/services/kanata/app_layers.py` |
| `todoist_reminders.py` | `widgets/yasb/todoist_reminders.py` |
| `todoist_reminders_schema.py` | `validation/widgets/yasb/todoist_reminders.py` |

- `kanata_mode`: kanata's current layer as one letter (the vim-like mode),
  listening to kanata's TCP server (`--port 9999`), no polling. Also:
  - `hints`: Space in WINDOW puts a letter over each window of the focused
    monitor; the letter focuses it;
  - `app_layers`: kanata's base layer by the app in focus (Premiere and After
    Effects: CapsLock tap = Delete; Zen: Win+W closes a tab), in place of
    komokana.
- `todoist_reminders`: the next Todoist task with a time today, in the bar; a
  card with Done, +10 min and Close, and an alarm, when its time comes. The
  token is Neovim's (`%LOCALAPPDATA%\nvim-data\todoist_token`).

Set up again:

    git clone https://github.com/amnweb/yasb.git ~/.config/yasb-src
    cd ~/.config/yasb-src && git switch -c kanata-mode v2.0.7
    copy the files above into place, commit
    py -3.14 -m venv .venv && .venv/Scripts/python -m pip install -e .
