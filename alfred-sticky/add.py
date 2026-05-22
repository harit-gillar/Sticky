#!/usr/bin/env python3
"""Alfred Run Script: fire the sticky:// URL to add the task."""
import os
import subprocess
import sys
import urllib.parse

task = sys.argv[1] if len(sys.argv) > 1 else ""
sticky_id = os.environ.get("stickyID", "")

if sticky_id and task.strip():
    url = "sticky://add?stickyID=%s&text=%s" % (
        sticky_id,
        urllib.parse.quote(task),
    )
    subprocess.run(["/usr/bin/open", url])
