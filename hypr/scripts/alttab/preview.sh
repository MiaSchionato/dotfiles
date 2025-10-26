#!/usr/bin/env bash
line="$1"
TMP_FILE="/tmp/hypr-alttab-preview-$$.png"

IFS=$'\t' read -r addr _ <<< "$line"
dim=${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}

grim -t png -l 0 -w "$addr" "$TMP_FILE"
chafa -f sixel -s "$dim" "$TMP_FILE"
rm "$TMP_FILE"
