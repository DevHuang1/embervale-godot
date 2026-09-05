#!/bin/sh
cd /Users/yuza/embervale-godot
rm -rf /tmp/ev_baseline
git worktree remove --force /tmp/ev_baseline 2>/dev/null
git worktree prune
# Check every project script individually; only the FIRST error of each file is most actionable.
find scripts -name '*.gd' | sort | while read s; do
  out=$(godot --headless --path . --check-only --script "res://$s" 2>&1)
  err=$(printf '%s' "$out" | grep -E 'Parse Error|Compile Error' | head -1)
  if [ -n "$err" ]; then
    printf '%s -> %s\n' "$s" "$err"
  fi
done
echo CHECK_ALL_DONE
