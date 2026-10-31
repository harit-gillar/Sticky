# Sticky — Alfred Workflow

Add and tick off tasks in your [Sticky](https://github.com/harit-gillar/Sticky) notes from Alfred.

Requires Alfred 5 with the **Powerpack**.

## Install

Double-click `Sticky.alfredworkflow` (build it with the command below if it's not present) and Alfred will import it.

To build the package from source:
```bash
cd alfred-sticky && zip -r ../Sticky.alfredworkflow . -x '.*' && cd ..
open ../Sticky.alfredworkflow
```

## Usage

### Add a task
Trigger Alfred and type:
```
sticky buy milk
```
A list shows every sticky (colour dot + open/total count). Arrow to the one you want and press **Enter** — the task is added and that sticky window comes to the front. Quotes are optional: `sticky "buy milk"` works too.

### Tick off a task
Type just:
```
sticky
```
Pick a sticky and press **Enter** to see its open tasks. Type to narrow them down, then press **Enter** on one — it's ticked off with that sticky's sound and confetti.

## How it works

- `filter.py` (Script Filter) reads `~/Library/Application Support/Sticky/stickies.json` (or the old sandbox container path from Sticky 1.1.x) and outputs one Alfred row per sticky, passing `stickyID` and `mode` (`add` when you typed a task, `pick` when you didn't) as workflow variables.
- A Conditional on `mode` sends `add` to `add.py` (Run Script), which fires `sticky://add?stickyID=…&text=…`.
- Anything else goes to `tasks.py` (Script Filter), which lists that sticky's open tasks; `tick.py` (Run Script) then fires `sticky://complete?stickyID=…&taskID=…`.
- The Sticky app handles both URLs in its AppDelegate and raises the window. `complete` only ever ticks a task, never unticks it.

Make sure Sticky has been launched at least once so its data file exists.
