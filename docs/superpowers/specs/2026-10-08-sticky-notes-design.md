# Sticky notes on the line

## Goal

Let the user hang sticky notes with to-do tasks on the same line that holds screenshots, and take them down (which deletes them) when the task is done.

Agreed with the user:

- Notes hang on the same rope, with the same clothespin, tilt, sway and fall animation as screenshots.
- Text only, stored locally, no network.
- Notes persist across launches.
- Creating a note: global shortcut, a "+" button on the line, and a menu bar item.
- Taking a note down and deleting it are the same gesture.

## 1. Model and persistence

`Pegged` gains a `kind`: a photo (`url`, `thumb`) or a note (`text`, `color`). `id`, `tilt`, `falling` and `flying` stay common. Code that uses `url` or `thumb` (copy, open, Markup, drag, `prune`, `reloadThumbnail`) applies to photos only. Hang, fall, `clear` and the breeze work for both kinds.

Persistence moves from an array of paths under `"pegged"` to a new key holding a JSON list of entries, in rope order:

- `{ "type": "photo", "path": ... }`
- `{ "type": "note", "text": ..., "color": ... }`

On restore, if the old key exists and the new one does not, the old paths are migrated once.

Capacity: `maxItems` is computed from the screen width (3 to 12) and now counts photos and notes together.

- When the line is full, only photos fall off, oldest first.
- If the line is full of notes, a new capture does not hang (the file stays where it is), and creating a note does nothing but beep.
- Notes never fall on their own. Only the user takes them down.

## 2. Creating and editing

Creation, all through `line.addNote()`:

- Global shortcut ⌃⌥N. `HotKey` stores actions in a dictionary keyed by id (it keeps a single static action today), so ⌃⌥T and ⌃⌥N coexist.
- A glass "+" button at the right end of the rope, visible only while the line is down. It registers in `hitRects` so the panel catches its click.
- A "New note" item in the menu bar menu.

`addNote()` appends an empty note, puts it in editing, and asks `AppDelegate` to bring the line down and keep it open (`pinned` / `keepOpen`).

Editing:

- `LinePanel` gains an `editing` flag. While true, `canBecomeKey` returns true and the panel becomes key without activating the app (it stays a `nonactivatingPanel`). The note shows a `TextEditor` with focus.
- Return commits. Shift-Return inserts a newline. Esc commits and keeps the text.
- A note that is empty on commit takes itself down.
- A click outside the note also commits, using the global click monitor `AppDelegate` already has.
- While editing, the line does not tuck away: `editing` counts as busy in `tick()`.
- When editing ends, `canBecomeKey` returns to false and focus goes back to the previous app.

Look: a square paper of about 130 pt in a pastel colour (yellow, pink, green or blue, chosen at random on creation), with shadow, tilt and sway like the photos. Text is limited to about 120 characters. No colour picker.

Risk to check first when implementing: that a non-activating `NSPanel` with a dynamic `canBecomeKey` reliably receives keyboard input on macOS 14 through 27. Fallback: a small separate window for typing, after which the note hangs.

## 3. Gestures, strings, tests

Gestures. Notes get a simpler grab view than `GrabArea`:

| Gesture | Action |
|:--|:--|
| Click | Edit |
| Corner cross | Take down and delete ("Pop" sound) |
| Right click | Menu with "Edit" and "Take down" |

Dragging a note does nothing in this version.

Strings. New strings ("New note", "Edit", "Write a task") go into the three `Localizable.strings` files, validated by `scripts/check-strings.swift`. The three READMEs get the ⌃⌥N shortcut in the gesture table and a sentence about notes.

Tests. A small test target for the pure logic:

- Save and restore photos and notes in order.
- Migration from the old key to the new one.
- Capacity drops only photos, never notes.
- An empty note takes itself down on commit.

Interaction (typing in the panel, focus, shortcut, "+" button) is checked by hand by running the app:

1. ⌃⌥N brings the line down with a focused empty note.
2. Type, press Return: the note stays and the line keeps open until the pointer leaves.
3. Click the note, edit, press Esc: text is kept.
4. Press ⌃⌥N, press Esc without typing: the note disappears.
5. Click outside while editing: commits.
6. Cross and right click "Take down" remove the note.
7. Quit and relaunch: photos and notes come back in the same order.
8. Fill the line: only photos fall, no note is lost.
9. While editing, the app you were in gets focus back afterwards.

## Out of scope

Reordering, colour picker, checkboxes or lists inside a note, sync, moving notes between screens.
