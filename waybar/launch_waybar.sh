#!/bin/bash

# Get current monitor resolution (assuming primary monitor)
# For Hyprland, `hyprctl monitors` is used.

MONITOR_INFO=$(hyprctl monitors | grep -E "^\s*Monitor" -A 1)
RESOLUTION=$(echo "$MONITOR_INFO" | grep -oP '\d+x\d+' | head -n 1)
WIDTH=$(echo "$RESOLUTION" | cut -d'x' -f1)

CONFIG_DIR="$HOME/.config/waybar"
CONFIG_FILE="$CONFIG_DIR/config.jsonc"

# Remove existing symlink if any
rm -f "$CONFIG_FILE"

if [ "$WIDTH" -eq 1920 ]; then
    ln -s "$CONFIG_DIR/config-1920.jsonc" "$CONFIG_FILE"
    echo "Using config-1920.jsonc"
elif [ "$WIDTH" -eq 2880 ]; then
    ln -s "$CONFIG_DIR/config-2880.jsonc" "$CONFIG_FILE"
    echo "Using config-2880.jsonc"
else
    # Fallback for unknown resolutions
    echo "Unknown resolution: $RESOLUTION. Using default config-1920.jsonc as fallback."
    ln -s "$CONFIG_DIR/config-1920.jsonc" "$CONFIG_FILE"
fi

# Launch Waybar
waybar
