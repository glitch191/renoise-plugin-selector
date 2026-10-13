--[[
  renoise-plugin-selector

  Adds an "Instrument Box:Load Plugin" context menu that lists the
  installed VST3 and VST2 instrument plugins in one list ("Vendor - Plugin"),
  and loads the chosen plugin into the selected instrument slot.
]]

local grouping = require("grouping")

local MENU_ROOT = "Instrument Box:Load Plugin"
local DUMP_LABEL = "Dump Plugin Info"
local DUMP_ENTRY = "--- " .. MENU_ROOT .. ":" .. DUMP_LABEL
local DUMP_FILE_NAME = "plugin-info-dump.txt"

-- Names of the menu entries added by the last build, so that a rebuild
-- removes exactly those entries and nothing else.
local added_entries = {}

-- Results of the last build, reused by the diagnostic dump.
local last_entries = {}
local last_build_seconds = 0


--------------------------------------------------------------------------------
-- Plugin list

-- Returns the raw available_plugin_infos list, or nil and an error message.
-- The list is only reachable through an instrument, so a song must exist.
local function fetch_plugin_infos()
  local song = renoise.song()
  if not song then
    return nil, "No song is loaded yet."
  end
  local ok, infos = pcall(function()
    return song.selected_instrument.plugin_properties.available_plugin_infos
  end)
  if not ok then
    return nil, tostring(infos)
  end
  return infos or {}
end


--------------------------------------------------------------------------------
-- Loading

local function load_plugin(path, label)
  local song = renoise.song()
  if not song then
    renoise.app():show_error("Load Plugin: no song is loaded.")
    return
  end

  local ok, result = pcall(function()
    local instrument = song.selected_instrument
    instrument:clear()
    return instrument.plugin_properties:load_plugin(path)
  end)

  if not ok then
    renoise.app():show_error(
      ("Load Plugin: could not load '%s'.\n\n%s"):format(label, tostring(result)))
  elseif not result then
    renoise.app():show_error(
      ("Load Plugin: Renoise could not load '%s'.\n\nPlugin path: %s\n\n" ..
       "The plugin may have been removed, or failed to initialize. " ..
       "Try rescanning plugins in Renoise's preferences."):format(label, path))
  else
    -- Open the plugin's editor window. Renoise shows a generic parameter
    -- editor for plugins without their own GUI.
    local opened, open_err = pcall(function()
      local device = song.selected_instrument.plugin_properties.plugin_device
      if device then
        device.external_editor_visible = true
      end
    end)
    if not opened then
      renoise.app():show_warning(
        ("Load Plugin: '%s' was loaded, but its editor could not be opened.\n\n%s"):format(
          label, tostring(open_err)))
    end
  end
end


--------------------------------------------------------------------------------
-- Diagnostic dump

local function value_text(value)
  return ("%s (%s)"):format(tostring(value), type(value))
end

local function write_dump()
  local infos, err = fetch_plugin_infos()
  if not infos then
    renoise.app():show_error("Dump Plugin Info: " .. err)
    return
  end

  local layout = grouping.build(infos)
  local entries = grouping.menu_entries(layout, MENU_ROOT, { DUMP_LABEL })

  local lines = {}
  local function add(line)
    lines[#lines + 1] = line
  end

  add("renoise-plugin-selector: plugin info dump")
  add("Renoise version: " .. tostring(renoise.RENOISE_VERSION))
  add("API version: " .. tostring(renoise.API_VERSION))
  add("Date: " .. os.date("%Y-%m-%d %H:%M:%S"))
  add(("Plugins reported by available_plugin_infos: %d"):format(#infos))
  add(("VST/VST3 instruments listed: %d, skipped: %d"):format(
    layout.plugin_count, #layout.skipped))
  add(("Last menu build: %d entries in %.3f s"):format(#last_entries, last_build_seconds))
  add("")

  add("== Raw available_plugin_infos ==")
  for index, info in ipairs(infos) do
    add(("[%d]"):format(index))
    add("  path:          " .. value_text(info.path))
    add("  name:          " .. value_text(info.name))
    add("  short_name:    " .. value_text(info.short_name))
    add("  favorite_name: " .. value_text(info.favorite_name))
    add("  is_favorite:   " .. value_text(info.is_favorite))
    add("  is_bridged:    " .. value_text(info.is_bridged))
  end
  add("")

  add("== Computed grouping ==")
  for _, section in ipairs(layout.sections) do
    add(section.name)
    for _, item in ipairs(section.items) do
      add(("  %s  [%s]  %s"):format(item.label, item.format, item.path))
    end
  end
  add("")

  add("== Skipped plugins ==")
  for _, skipped in ipairs(layout.skipped) do
    add(("  %s  (%s)  %s"):format(
      tostring(skipped.info.name), skipped.reason, tostring(skipped.info.path)))
  end
  add("")

  add("== Menu entry names ==")
  for _, entry in ipairs(entries) do
    add("  " .. entry.name)
  end

  local file_path = renoise.tool().bundle_path .. DUMP_FILE_NAME
  local file, open_err = io.open(file_path, "w")
  if not file then
    renoise.app():show_error("Dump Plugin Info: could not write the file.\n\n" .. tostring(open_err))
    return
  end
  file:write(table.concat(lines, "\n"), "\n")
  file:close()

  renoise.app():show_message("Plugin info written to:\n\n" .. file_path)
end


--------------------------------------------------------------------------------
-- Menu building

local function remove_menu_entries()
  local tool = renoise.tool()
  for _, name in ipairs(added_entries) do
    if tool:has_menu_entry(name) then
      tool:remove_menu_entry(name)
    end
  end
  added_entries = {}
end

local function add_entry(name, invoke)
  local tool = renoise.tool()
  if tool:has_menu_entry(name) then
    return
  end
  tool:add_menu_entry { name = name, invoke = invoke }
  added_entries[#added_entries + 1] = name
end

local function build_menu()
  local started = os.clock()

  local infos = fetch_plugin_infos()
  if not infos then
    -- No song yet (early in startup): app_new_document will rebuild.
    return
  end

  local layout = grouping.build(infos)
  local entries = grouping.menu_entries(layout, MENU_ROOT, { DUMP_LABEL })

  remove_menu_entries()
  for _, entry in ipairs(entries) do
    local path, label = entry.path, entry.label
    add_entry(entry.name, function()
      load_plugin(path, label)
    end)
  end
  add_entry(DUMP_ENTRY, write_dump)

  last_entries = entries
  last_build_seconds = os.clock() - started
end

local function rebuild_menu()
  local ok, err = pcall(build_menu)
  if not ok then
    -- Keep the diagnostic entry reachable even when the build fails.
    pcall(add_entry, DUMP_ENTRY, write_dump)
    renoise.app():show_warning("Load Plugin: could not build the plugin menu.\n\n" .. tostring(err))
  end
end


--------------------------------------------------------------------------------
-- Notifiers

-- The diagnostic entry exists from the start, even before a song is loaded.
add_entry(DUMP_ENTRY, write_dump)

local tool = renoise.tool()

tool.tool_finished_loading_observable:add_notifier(rebuild_menu)

-- Fires on every new or loaded song. Renoise offers no notification for a
-- plugin rescan, so this is also when a rescan becomes visible in the menu.
tool.app_new_document_observable:add_notifier(rebuild_menu)
