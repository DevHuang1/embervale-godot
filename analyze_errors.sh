#!/bin/sh
grep -B1 'at: GDScript::reload' /tmp/run3.txt | paste - - | sed 's/.*Parse Error: //; s/at: GDScript::reload //' | sort | uniq -c | sort -rn | head -60
