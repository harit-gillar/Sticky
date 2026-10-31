# Sticky — Alfred Workflow

Add tasks to your [Sticky](https://github.com/harit-gillar/Sticky) notes from Alfred.

Requires Alfred 5 with the **Powerpack**.

## Install

Double-click `Sticky.alfredworkflow` (build it with the command below if it's not present) and Alfred will import it.

To build the package from source:
```bash
cd alfred-sticky && zip -r ../Sticky.alfredworkflow . -x '.*' && cd ..
open ../Sticky.alfredworkflow
```

## Usage

Trigger Alfred and type:
```
sticky buy milk
```
A list shows every sticky (colour dot + open/total count). Arrow to the one you want and press **Enter** — the task is added and that sticky window comes to the front.

## How it works

- `filter.py` (Script Filter) reads `~/Library/Containers/com.stickytodos.app/Data/Library/Application Support/Sticky/stickies.json` and outputs one Alfred row per sticky, passing the chosen `stickyID` as a workflow variable.
- `add.py` (Run Script) fires `sticky://add?stickyID=…&text=…`.
- The Sticky app handles that URL in its AppDelegate, appends the task, and raises the window.

Make sure Sticky has been launched at least once so its data file exists.
