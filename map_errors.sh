#!/bin/sh
# Print unique "res://path:line  error" pairs from a runtime run log.
grep -A1 'SCRIPT ERROR' /tmp/run3.txt | grep 'at: GDScript::reload' | sed 's#.*at: GDScript::reload (res://##; s#)##' | sort -u | head -60

