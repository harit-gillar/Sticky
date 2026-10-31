#!/usr/bin/env python3
"""Alfred Run Script: fire the sticky:// URL to tick off the chosen task."""
import os
import subprocess
import urllib.parse

sticky_id = os.environ.get("stickyID", "")
task_id = os.environ.get("taskID", "")

if sticky_id and task_id:
    url = "sticky://complete?stickyID=%s&taskID=%s" % (
        urllib.parse.quote(sticky_id),
        urllib.parse.quote(task_id),
    )
    subprocess.run(["/usr/bin/open", url])
