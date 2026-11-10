# Files removed from WeBeep

What Beep does when content disappears from a course, and what to expect on disk.

## Behaviour

A sync never deletes a file, a module or a section while the app is running. A view may still
hold the row, and reading a deleted SwiftData model is a fatal error (the Mac crash of 0.2.0 (21)).
Content that is gone from WeBeep is marked with `removedAt` instead.

| The file was | In the app | On disk |
|---|---|---|
| downloaded, "Keep files removed from WeBeep" on (default) | "Removed from WeBeep" group at the bottom of its folder, or of its section for a single resource | renamed `[removed 2026-11-10] name.pdf` (`[rimosso …]` in Italian), same folder |
| not downloaded | hidden, deleted from the store at the next launch | nothing to keep |
| downloaded, keeping off | hidden, deleted from the store at the next launch | left as it is, where a new file with the same name can replace it |

The rename exists because the identity of a file is its path inside the module: a new file
with the same name would otherwise be treated as an update and written over the removed copy.
Renaming also frees the identity, so the new file is a new row.

Removed files do not count in totals, badges, automatic downloads, Recent, the widget or Spotlight.
Global search still finds the ones kept on disk. "Remove download" on a removed file deletes the
copy and the entry.

If the same content comes back while its row still holds its identity (a file that was never
downloaded, or any module), the same row is restored and the file shows as new.

Code: `Indexer.upsertContents` (marking), `RemovedContent` (rename, purge at launch),
`LocalFiles.markRemoved`, settings keys `settings.removedFiles.keep` and `settings.removedFiles.display`.

## Known limitation: hidden and shown again

WeBeep does not tell a student whether a teacher deleted a module or only hid it: in both cases
it stops appearing in the course contents. Beep treats both as a removal.

So when a teacher hides a folder and shows it again later:

1. at the first sync after hiding, the downloaded files are renamed `[removed <date>] …` and
   move to the "Removed from WeBeep" group;
2. at the first sync after showing, the folder comes back and its files are new: in a course with
   automatic download they are downloaded again under their normal names.

Result: two copies on disk, the renamed one and the fresh one. Nothing is lost. The renamed copies
can be deleted with "Remove download" in the removed group.

How often this happens is not measured. In the two snapshots of a real store taken on 8 and
10 November 2026 (57 courses, about 900 modules) no module disappeared, but two days say little:
teachers do hide solutions or exam material for a while. A grace period before renaming would
avoid the duplicate; it is not implemented.

## Testing without a teacher

- Unit tests: `IndexerTests` (marking and restoring), `RemovedContentTests` (rename, duplicates, purge).
- Demo data: launch a debug build with `-demo -demoRemoved` to get a course with removed files
  and the groups already open.
- Real courses: launch a debug build with `-simulateRemoved "lesson 2"`. The sync then behaves as
  if WeBeep no longer returned the files whose name contains that text; the rest is the real path
  (marking, rename in the sync folder, removed group, log line in the `sync` category). Launch again
  without the argument and the file comes back as new, which reproduces the limitation above.
  The debug build uses the same store as the installed app: quit the installed one first.
