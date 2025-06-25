#!/bin/bash

# Define the output file with the current date and time
output_file="$HOME/Videos/$(date '+%Y-%m-%d_%H-%M-%S').mp4"

# Check if a recording is already running
if pgrep -x "ffmpeg" > /dev/null; then
    echo "Recording is already in progress."
    exit 1
fi

# Start recording using ffmpeg

 wf-recorder -f "$HOME/Videos/screenrecodrings/$(date '+%Y-%m-%d_%H-%M-%S').mp4" -r 30 --audio=bluez_output.62_A2_CF_10_65_E2.1.monitor --codec libx264 --crf 28 &
notify-send -i ~/.config/sxhkd/scripts/camera.png "ffmpeg" "Recording started"
