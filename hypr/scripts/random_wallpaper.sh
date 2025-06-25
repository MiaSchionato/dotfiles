#!/usr/bin/env bash
WALLPAPER_DIR="$HOME/.wallpapers/"
CURRENT_WALL=$(hyprctl hyprpaper listloaded)
WALLPAPER=$(find "$WALLPAPER_DIR" -type f ! -name "$(basename "$CURRENT_WALL")" | shuf -n 1)
hyprctl hyprpaper reload ,"$WALLPAPER"
if ! pgrep -x hyprpaper > /dev/null; then
   # Se não estiver, inicia o hyprpaper em background
   # IMPORTANTE: Use aqui o mesmo comando que você usa no seu hyprland.conf
   hyprpaper & /.config/hypr/scripts/random_wallpaper.sh
fi
