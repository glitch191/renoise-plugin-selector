# renoise-plugin-selector

A Renoise tool that adds a **Load Plugin** menu to the Instrument Box context
menu. It lists your VST3 and VST2 instrument plugins the same way as the left
pane of Renoise's Plugin tab, and loads the chosen plugin into the selected
instrument slot in one click.

<!-- ![The Load Plugin menu in the Instrument Box context menu](docs/screenshots/context-menu.png) -->
<!-- *The Load Plugin menu, opened with a right-click in the Instrument Box.* -->

## Compatibility

- Renoise 3.5.x (scripting API 6.2)
- Windows
- VST3 and VST2 instrument plugins only (no effects, no AU or other formats)

## Installation

**From a release:** download `renoise-plugin-selector-<version>.xrnx` from the
repository's **Releases** page and drag it onto the Renoise window.

**From the source:** run the install script from the repository folder:

```powershell
.\scripts\install-tool.ps1 -RenoiseVersion 3.5.4
```

The script copies the tool into
`%APPDATA%\Renoise\V<version>\Scripts\Tools\<tool id>.xrnx` and writes nothing
else. If exactly one Renoise 3.5.x folder exists, `-RenoiseVersion` can be
omitted. With several versions, or none, it stops and asks for
`-RenoiseVersion` or `-ToolsPath`. If Renoise is open, use
**Tools > Reload All Tools** (shown when scripting development tools are
enabled in the preferences) or restart Renoise.

### Verifying the checksum

Each release also has a `.sha256` file. In PowerShell:

```powershell
Get-FileHash -Algorithm SHA256 .\renoise-plugin-selector-1.0.xrnx
```

The hash must match the one in `renoise-plugin-selector-1.0.xrnx.sha256`.

## Usage

Right-click an instrument slot in the Instrument Box (top right of Renoise)
and open **Load Plugin**:

```
Load Plugin
  Favorites      > Plugin
  VST3           > Vendor > Plugin
  VST            > Vendor > Plugin
  Dump Plugin Info
```

- Vendors are grouped by their exact name, as Renoise shows them, sorted by
  character code (uppercase before lowercase), like the Plugin tab.
- Plugins without a vendor are listed under **Unknown**, last.
- Bridged plugins are listed and can be loaded.

**Loading replaces the selected instrument.** The slot is cleared and the
plugin is loaded, whether the slot was empty or not, without confirmation.
If Renoise cannot load the plugin, an error message is shown.

## Known limitations

- **Vendor detection.** The scripting API has no vendor field. The tool reads
  it from the plugin name Renoise provides (`Vendor: Plugin`). If a vendor or
  position differs from the Plugin tab, please report it with a diagnostic
  file.
- **Name cleanup.** Colons and slashes in names are replaced by `-` in the
  menu, because `:` separates menu levels. The real plugin path is unchanged.
  Two plugins with the same name under one vendor get a ` (2)` suffix.
- **Favorites** come from the API's `is_favorite` field, labelled with
  `favorite_name`.
- **Menu updates.** The menu is rebuilt when the tool loads and whenever a
  song is created or opened. Renoise does not notify tools about a plugin
  rescan, so after a rescan or a favorite change, create or open a song to
  refresh the menu.

## Troubleshooting

Choose **Load Plugin > Dump Plugin Info**. It writes `plugin-info-dump.txt`
in the tool folder with the raw plugin list from Renoise (path, name, short
name, favorite name, favorite and bridged flags) and the computed menu
layout. Errors are also shown in **Tools > Scripting Terminal & Editor**.

A manual test procedure is in [docs/TESTING.md](docs/TESTING.md).

## Releases

Publishing a GitHub release runs `.github/workflows/release.yml`, which builds
`renoise-plugin-selector-<tag>.xrnx` and its `.sha256` file and attaches them
to the release. The packaged `manifest.xml` gets the tag as its version
(without the leading `v`) when the tag is a plain number such as `v1.2`;
otherwise the version from the repository manifest is kept. The workflow can
also be started by hand (**Actions > Release > Run workflow**); the package is
then available as a workflow artifact.

To build locally: `.\scripts\build-xrnx.ps1 -Tag v1.0` (output in `dist/`).

## Project structure

```
manifest.xml               Tool manifest
main.lua                   Menu building, loading, diagnostic
grouping.lua               Pure grouping and name cleanup logic
tests/                     Offline tests with a fake Renoise API
scripts/install-tool.ps1   Local installation
scripts/build-xrnx.ps1     Package build (used by the workflow)
docs/                      Test procedure and screenshots
```

Run the offline tests with a Lua 5.1 compatible interpreter:
`luajit tests/run_tests.lua`. All plugin and vendor names in the tests are
fictional sample data.

## License

MIT, see [LICENSE](LICENSE).
