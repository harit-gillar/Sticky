#!/usr/bin/env python3
"""Alfred Script Filter: list stickies.

With text after "sticky ", each row adds that text as a task (mode=add).
With no text, each row opens that sticky's open tasks to tick off (mode=pick).
"""
import json
import os
import sys

QUERY = sys.argv[1] if len(sys.argv) > 1 else ""
task = QUERY.strip()
# Allow `sticky "new task"` — drop one pair of surrounding quotes
for open_q, close_q in (('"', '"'), ("'", "'"), ("“", "”"), ("‘", "’")):
    if len(task) >= 2 and task.startswith(open_q) and task.endswith(close_q):
        task = task[1:-1].strip()
        break

# Sticky 1.2.0+ isn't sandboxed; older versions kept their data in the container
PATHS = [
    os.path.expanduser("~/Library/Application Support/Sticky/stickies.json"),
    os.path.expanduser(
        "~/Library/Containers/com.stickytodos.app/Data/Library/"
        "Application Support/Sticky/stickies.json"
    ),
]
PATH = next((p for p in PATHS if os.path.exists(p)), PATHS[0])
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
        if task:
            mode = "add"
            valid = True
            subtitle = f'Add "{task}"  ·  {remaining}/{total} open'
        else:
            mode = "pick"
            valid = remaining > 0
            if valid:
                subtitle = f"Enter to tick off a task  ·  {remaining}/{total} open"
            else:
                subtitle = "Nothing to tick off  ·  type a task to add one"
        items.append(
            {
                "uid": s["id"],
                "title": f'{emoji}  {s.get("title", "Untitled")}',
                "subtitle": subtitle,
                "arg": task,
                "valid": valid,
                "variables": {"stickyID": s["id"], "mode": mode},
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
