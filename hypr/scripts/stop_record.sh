
#!/bin/bash

# Kill the ffmpeg process
pkill -x wf-recorder

notify-send -i ~/.config/sxhkd/scripts/camera.png "ffmpeg" "Recording stopped"
