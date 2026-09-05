#!/bin/sh
# Baseline HEAD~1 run
rm -rf /tmp/ev_baseline
git -C /Users/yuza/embervale-godot worktree add /tmp/ev_baseline HEAD~1 >/tmp/wt.log 2>&1
godot --headless --path /tmp/ev_baseline res://scenes/main/main.tscn --quit-after 180 >/tmp/baseline_run.txt 2>&1
printf 'BASELINE_SCRIPT_ERRORS=%d\n' "$(grep -c 'SCRIPT ERROR' /tmp/baseline_run.txt)"
grep -E 'Failed to load script.*\.gd|hides an autoload' /tmp/baseline_run.txt | sort -u | head -20
echo BASELINE_DONE
