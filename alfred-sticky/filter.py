#!/usr/bin/env python3
"""Alfred Script Filter: list stickies, each as 'add <task> to this sticky'."""
import json
import os
import sys

QUERY = sys.argv[1] if len(sys.argv) > 1 else ""
task = QUERY.strip()

PATH = os.path.expanduser(
    "~/Library/Containers/com.stickytodos.app/Data/Library/"
    "Application Support/Sticky/stickies.json"
)
EMOJI = {
    "yellow": "🟡",
    "pink": "🩷",
    "green": "🟢",
    "blue": "🔵",
    "purple": "🟣",
    "orange": "🟠",
}

items = []
try:
    with open(PATH) as f:
        data = json.load(f)
    for s in data.get("stickies", []):
        preset = ((s.get("colorTheme") or {}).get("preset") or {}).get("_0", "")
        emoji = EMOJI.get(preset, "⚪")
        tasks = s.get("tasks", [])
        remaining = sum(1 for t in tasks if not t.get("isCompleted"))
        total = len(tasks)
        valid = bool(task)
        if valid:
            subtitle = f'Add "{task}"  ·  {remaining}/{total} open'
        else:
            subtitle = f'Type a task after "sticky "  ·  {remaining}/{total} open'
        items.append(
            {
                "uid": s["id"],
                "title": f'{emoji}  {s.get("title", "Untitled")}',
                "subtitle": subtitle,
                "arg": task,
                "valid": valid,
                "variables": {"stickyID": s["id"]},
            }
        )
    if not items:
        items.append(
            {
                "title": "No stickies found",
                "subtitle": "Has Sticky been launched at least once?",
                "valid": False,
            }
        )
except Exception as e:  # noqa: BLE001
    items.append(
        {
            "title": "Couldn't read Sticky data",
            "subtitle": str(e),
            "valid": False,
        }
    )

print(json.dumps({"items": items}))
