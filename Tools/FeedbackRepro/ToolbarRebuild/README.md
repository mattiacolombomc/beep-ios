# Feedback: toggling `ToolbarContent.hidden(_:)` re-evaluates every toolbar Menu's content

**Environment:** macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), SwiftUI app with the Liquid Glass toolbar.

**Steps:** `xcodegen generate && xcodebuild -scheme ToolbarRebuild -configuration Release build`,
then run `ToolbarRebuild.app/Contents/MacOS/ToolbarRebuild` with one of:

| Argument | What changes 10 times |
|---|---|
| `-hidden` | `.hidden(_:)` on an unrelated toolbar item |
| `-searchable` | the text of `.searchable` |
| `-textfield` | the text of a TextField in the content (control) |

**Expected:** the toolbar `Menu` (20 items) is not re-evaluated, since nothing it reads changes.

**Actual (measured):**

| Argument | Menu items evaluated | Main thread busy |
|---|---|---|
| `-textfield` | 0 | 10 ms |
| `-searchable` | 0 | 31 ms |
| `-hidden` | 200 (the whole menu, every toggle) | 258 ms |

Time Profiler shows `ToolbarBridge.makeStorage`, `AppKitToolbarItem.updateMenuFormRepresentation`
and `-[NSToolbarView layout]` on every toggle. With a few items and a larger menu, each toggle
re-tiles the toolbar for tens of milliseconds and closes any open toolbar menu.

**Workaround:** add and remove the item with `if` inside the toolbar builder, or keep the item
and change only its content.
