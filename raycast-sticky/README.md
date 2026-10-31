# Sticky — Raycast Extension

Add tasks to your [Sticky](https://github.com/harit-gillar/Sticky) notes from Raycast.

## Setup

1. Make sure Sticky is installed and has been run at least once (so it creates its data file).
2. Install dependencies:
   ```bash
   cd raycast-sticky
   npm install
   ```
3. Run in development mode:
   ```bash
   npm run dev
   ```
   This opens Raycast with the extension loaded.

Alternatively in Raycast: `Import Extension` → point at this folder.

## Usage

1. Open Raycast (your hotkey)
2. Type **Add Sticky Task**
3. Pick which sticky to add to from the dropdown
4. Type your task
5. Hit ⌘↵ to submit

The task gets added and Sticky pops the chosen sticky to the front.

## How it works

- The extension reads `~/Library/Application Support/Sticky/stickies.json` (or the old sandbox container path from Sticky 1.1.x) to populate the dropdown
- On submit, it fires a `sticky://add?stickyID=...&text=...` URL
- The Sticky app intercepts the URL via its `application(_:open:)` AppDelegate handler, appends the task, and brings the window forward
