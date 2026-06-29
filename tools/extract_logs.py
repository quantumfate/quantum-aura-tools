#!/usr/bin/env python3
"""Extract this addon's entries from the LibDebugLogger SavedVariables file.

LibDebugLogger stores log entries as a Lua table (LibDebugLoggerLog) in
SavedVariables/LibDebugLogger.lua. ESO only writes SavedVariables to disk on
/reloadui or logout, so reload before reading. This filters the entries by logger
tag and prints them as readable `time [LEVEL] tag  message` lines.

Usage:
    python3 tools/extract_logs.py <LibDebugLogger.lua> [--tag Quantum] [--level D]
"""

import argparse
import re
import sys

LEVEL_ORDER = {"V": 0, "D": 1, "I": 2, "W": 3, "E": 4}

# One log entry: a numbered block of fields [1]..[7]. Field [6] (message) may span
# lines, so match non-greedily up to the start of field [7].
ENTRY_RE = re.compile(
    r'\[\d+\] =\s*\{\s*'
    r'\[1\] = (?P<ms>\d+),\s*'
    r'\[2\] = "(?P<time>[^"]*)",\s*'
    r'\[3\] = \d+,\s*'
    r'\[4\] = "(?P<level>[^"]*)",\s*'
    r'\[5\] = "(?P<tag>[^"]*)",\s*'
    r'\[6\] = "(?P<msg>.*?)",\s*'
    r'\[7\] = ',
    re.DOTALL,
)


def unescape(s):
    return s.replace('\\"', '"').replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--tag", default="Quantum", help="substring match on the logger tag")
    ap.add_argument("--level", default="V", help="minimum level: V/D/I/W/E")
    args = ap.parse_args()

    try:
        text = open(args.path, encoding="utf-8", errors="replace").read()
    except OSError as e:
        sys.exit(f"cannot read {args.path}: {e}")

    floor = LEVEL_ORDER.get(args.level.upper(), 0)
    tag = args.tag.lower()
    n = 0
    for m in ENTRY_RE.finditer(text):
        if tag not in m["tag"].lower():
            continue
        if LEVEL_ORDER.get(m["level"], 0) < floor:
            continue
        msg = unescape(m["msg"]).replace("\n", "\n    ")
        print(f'{m["time"]} [{m["level"]}] {m["tag"]}  {msg}')
        n += 1

    if n == 0:
        print(f"(no entries matching tag '{args.tag}' at level >= {args.level}; "
              f"check LibDebugLogger minLogLevel and that you /reloadui'd)", file=sys.stderr)


if __name__ == "__main__":
    main()
