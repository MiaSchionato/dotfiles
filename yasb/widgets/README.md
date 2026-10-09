# yasb widgets of my own

yasb only loads widgets from its source tree, so yasb runs from a clone
(`~/.config/yasb-src`, tag v2.0.7 plus the local branch `kanata-mode`, in a
Python 3.14 venv; the Desktop stack task starts it). These are copies of what
that branch adds:

- `kanata_mode.py` → `src/core/widgets/yasb/kanata_mode.py`
- `kanata_mode_schema.py` → `src/core/validation/widgets/yasb/kanata_mode.py`

`kanata_mode` shows kanata's current layer as one letter (the vim-like mode),
listening to kanata's TCP server (`--port 9999`): no polling.

Set up again:

    git clone https://github.com/amnweb/yasb.git ~/.config/yasb-src
    cd ~/.config/yasb-src && git switch -c kanata-mode v2.0.7
    copy the two files above into place, commit
    py -3.14 -m venv .venv && .venv/Scripts/python -m pip install -e .
