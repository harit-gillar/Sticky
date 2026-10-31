#!/usr/bin/env python3
"""Alfred Script Filter: list the chosen sticky's open tasks to tick off.

Alfred filters the rows as you type, so the query is not used here.
"""
import json
import os

PATH = os.path.expanduser(
    "~/Library/Containers/com.stickytodos.app/Data/Library/"
    "Application Support/Sticky/stickies.json"
)

sticky_id = os.environ.get("stickyID", "")

items = []
try:
    with open(PATH) as f:
        data = json.load(f)
    sticky = next((s for s in data.get("stickies", []) if s.get("id") == sticky_id), None)
    if sticky is None:
        items.append(
            {
                "title": "Sticky not found",
                "subtitle": "It may have been deleted. Type \"sticky\" to start again.",
                "valid": False,
            }
        )
    else:
        name = sticky.get("title", "Untitled")
        open_tasks = [t for t in sticky.get("tasks", []) if not t.get("isCompleted")]
        for t in open_tasks:
            title = (t.get("title") or "").strip() or "(empty task)"
            # Multi-line tasks (Shift+Enter) show their first line
            first_line = title.splitlines()[0]
            items.append(
                {
                    "uid": t["id"],
                    "title": f"☐  {first_line}",
                    "subtitle": f"Enter to tick off  ·  {name}",
                    "match": title,
                    "arg": "",
                    "valid": True,
                    "variables": {"stickyID": sticky_id, "taskID": t["id"]},
                }
            )
        if not open_tasks:
            items.append(
                {
                    "title": "No open tasks 🎉",
                    "subtitle": f"Everything on {name} is done",
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
