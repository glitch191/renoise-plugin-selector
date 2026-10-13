# Manual test procedure in Renoise

These checks need Renoise itself and are done by hand. Offline logic tests
run with `luajit tests/run_tests.lua`.

## 1. Install

```powershell
.\scripts\install-tool.ps1 -RenoiseVersion 3.5.4
```

Restart Renoise, or if it is open use **Tools > Reload All Tools** (this
item is shown when *Preferences > Scripting > Show scripting development
tools* is on).

## 2. Startup

1. Open **Tools > Scripting Terminal & Editor**: no error from
   `RenoisePluginSelector` in the terminal.
2. Right-click an instrument slot in the Instrument Box (top right).
   A **Load Plugin** submenu is shown.

## 3. Menu layout

1. Open **Load Plugin**. Expected order: **Favorites** (only when there are
   favorites), **VST3**, **VST**, then **Dump Plugin Info** after a separator.
2. Open **VST3** and compare it with the left pane of the **Plugin** tab:
   same vendors, same order (uppercase names before lowercase ones), same
   plugins under each vendor.
3. Pick a few plugins in **VST** and check the vendor and position the same way.
4. No effect plugin appears anywhere.

## 4. Loading

1. Select an empty slot and choose a plugin: it loads and its editor
   behaves as usual.
2. Select a slot that holds samples or another plugin and choose a plugin:
   the slot is replaced without any confirmation.
3. If you have a broken or missing plugin, choosing it shows an error
   message instead of failing silently.

## 5. Favorites and rebuild

1. In the Plugin tab, mark one instrument as favorite.
2. Create a new song (**File > New Song**). Right-click the Instrument Box:
   the plugin is now under **Favorites**.
3. Remove the favorite, create a new song again: it is gone.
4. Open the menu several times after several new songs: no duplicated
   entries.

## 6. Diagnostic

1. Choose **Load Plugin > Dump Plugin Info**. A message gives the file path.
2. Open `plugin-info-dump.txt` in the tool folder and check that each
   plugin's `name` looks like `Vendor: Plugin`, and that `path` contains
   `/VST3/` or `/VST/`. Send this file back if anything looks wrong.
