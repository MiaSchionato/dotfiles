#!/usr/bin/env bash
hyprctl -q keyword animations:enabled true

hyprctl -q --batch "keyword unbind ALT, TAB ; keyword unbind ALT SHIFT, TAB ; keyword bind ALT, TAB, exec, /home/miguel/.config/hypr/scripts/alttab/enable.sh 'down' ; keyword bind ALT SHIFT, TAB, exec, /home/miguel/.config/hypr/scripts/alttab/enable.sh 'up' ; dispatch submap reset"