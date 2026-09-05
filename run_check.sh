#!/bin/sh
godot --headless --path . res://scenes/main/main.tscn --quit-after 180 > /tmp/run3.txt 2>&1
printf 'PARSE_SCRIPT_ERRORS=%d\n' "$(grep -c 'SCRIPT ERROR' /tmp/run3.txt)"
grep -E 'hides an autoload|Failed to load script|Parse Error' /tmp/run3.txt | sort -u | head -25
echo RUN_DONE
