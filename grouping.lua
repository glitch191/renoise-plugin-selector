--[[
  grouping.lua

  Pure Lua logic (no Renoise API calls) that turns the list returned by
  renoise.InstrumentPluginProperties.available_plugin_infos into a single
  flat menu:

    Load Plugin > Vendor - Plugin   (favorites first)
                  ---------------
                  Vendor - Plugin   (all other plugins, VST and VST3)

  Kept separate from main.lua so it can be tested outside of Renoise.

  Vendor detection: Renoise stores each plugin's display name as
  "Vendor: Plugin" (the same string it caches as DisplayName in its plugin
  database). The vendor is the text before the first ": ". Vendors are
  used by their exact name, without merging variants, as Renoise does.

  Sorting: Renoise sorts by character code, so uppercase names come before
  lowercase ones ("Waves" before "retro-chip-vst"). The same order is used
  here. Plugins without a vendor are listed as "Unknown", last.
]]

local M = {}

M.UNKNOWN_VENDOR = "Unknown"

-- Vendor names that Renoise uses when a plugin reports no vendor.
local UNKNOWN_VENDOR_NAMES = {
  [""] = true,
  ["-"] = true,
  ["unknown"] = true,
  ["unknown vendor"] = true,
}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Make a string safe to use as one level of a Renoise menu path.
-- ":" separates menu levels, "/" and "\" may be read as path separators,
-- and leading dashes would turn the entry into a separator.
function M.sanitize(s)
  s = tostring(s or "")
  s = s:gsub("%c", " ")
  s = s:gsub("[:/\\]", "-")
  s = s:gsub("%s+", " ")
  s = trim(s)
  s = s:gsub("^[-%s]+", "")
  if s == "" then
    s = "Unnamed"
  end
  return s
end

-- Plugin format from a plugin path such as "Audio/Generators/VST3/<id>".
-- Only the directory segments are inspected, never the plugin id itself.
-- Returns "VST3", "VST" or nil for any other format.
function M.format_of(path)
  if type(path) ~= "string" then
    return nil
  end
  local segments = {}
  for segment in path:gmatch("[^/]+") do
    segments[#segments + 1] = segment
  end
  for i = 1, #segments - 1 do
    local s = segments[i]:upper()
    if s == "VST3" then
      return "VST3"
    elseif s == "VST" or s == "VST2" then
      return "VST"
    end
  end
  return nil
end

-- Split a Renoise display name "Vendor: Plugin" into its two parts.
-- Names without ": " have an empty vendor.
function M.split_vendor(name)
  name = tostring(name or "")
  local pos = name:find(": ", 1, true)
  if not pos then
    return "", trim(name)
  end
  return trim(name:sub(1, pos - 1)), trim(name:sub(pos + 2))
end

function M.is_unknown_vendor(vendor)
  return UNKNOWN_VENDOR_NAMES[trim(vendor or ""):lower()] == true
end

-- The API documents is_favorite and is_bridged as strings, so accept
-- both booleans and their string or numeric forms.
function M.truthy(value)
  return value == true or value == "true" or value == 1 or value == "1"
end

local function compare_items(a, b)
  if a.label ~= b.label then
    return a.label < b.label
  end
  if a.format ~= b.format then
    return a.format < b.format
  end
  return a.path < b.path
end

-- Menu entries must have unique names. When two items of one section
-- share a label in different formats (the same plugin in VST and VST3),
-- the format is added, and any remaining clash gets a counter. Comparison
-- ignores case to be safe with menus.
local function make_labels_unique(items)
  local formats = {}
  for _, item in ipairs(items) do
    local key = item.label:lower()
    formats[key] = formats[key] or {}
    formats[key][item.format] = true
  end
  for _, item in ipairs(items) do
    local set = formats[item.label:lower()]
    if set.VST and set.VST3 then
      item.label = item.label .. " (" .. item.format .. ")"
    end
  end
  local seen = {}
  for _, item in ipairs(items) do
    local base = item.label
    local n = 1
    while seen[item.label:lower()] do
      n = n + 1
      item.label = base .. " (" .. n .. ")"
    end
    seen[item.label:lower()] = true
  end
end

--[[
  Build the layout from a list of plugin infos.

  Returns a table:
    {
      favorites = { item, ... },
      sections = {                       -- vendors sorted, Unknown last
        { name = "Vendor", items = { item, ... } }, ...
      },
      skipped = { { info = info, reason = "..." }, ... },
      plugin_count = <number of VST/VST3 instruments listed>,
    }
  Each item is { label = <plugin label>, section = <vendor label>,
  path = <original path>, format = "VST" | "VST3", favorite = <boolean>,
  name = <raw name> }. Favorites are listed in both favorites and their
  vendor section; menu_entries shows them only once.
]]
function M.build(infos)
  local result = { favorites = {}, sections = {}, skipped = {}, plugin_count = 0 }
  local by_vendor = {}
  local unknown = nil

  for _, info in ipairs(infos or {}) do
    local format = M.format_of(info.path)
    if not format then
      result.skipped[#result.skipped + 1] = { info = info, reason = "not a VST or VST3 plugin" }
    else
      local vendor, plugin_name = M.split_vendor(info.name)
      if plugin_name == "" then
        plugin_name = tostring(info.short_name or "")
      end

      local section
      if M.is_unknown_vendor(vendor) then
        if not unknown then
          unknown = { name = M.UNKNOWN_VENDOR, items = {} }
        end
        section = unknown
      else
        local section_name = M.sanitize(vendor)
        section = by_vendor[section_name]
        if not section then
          section = { name = section_name, items = {} }
          by_vendor[section_name] = section
          result.sections[#result.sections + 1] = section
        end
      end

      local favorite = M.truthy(info.is_favorite)
      section.items[#section.items + 1] = {
        label = M.sanitize(plugin_name),
        section = section.name,
        path = info.path,
        format = format,
        favorite = favorite,
        name = tostring(info.name or ""),
      }
      result.plugin_count = result.plugin_count + 1

      if favorite then
        local favorite_label = info.favorite_name
        if type(favorite_label) ~= "string" or trim(favorite_label) == "" then
          favorite_label = plugin_name
        end
        result.favorites[#result.favorites + 1] = {
          label = M.sanitize(favorite_label),
          section = section.name,
          path = info.path,
          format = format,
          favorite = true,
          name = tostring(info.name or ""),
        }
      end
    end
  end

  table.sort(result.sections, function(a, b)
    return a.name < b.name
  end)
  if unknown then
    result.sections[#result.sections + 1] = unknown
  end

  for _, section in ipairs(result.sections) do
    table.sort(section.items, compare_items)
  end
  local function display(item)
    return item.section .. " - " .. item.label
  end
  table.sort(result.favorites, function(a, b)
    if display(a) ~= display(b) then
      return display(a) < display(b)
    end
    return compare_items(a, b)
  end)

  return result
end

--[[
  Turn a layout into the ordered list of menu entries, all directly under
  the root:
    { { name = "<root>:Vendor - Plugin", path = "...", label = "..." }, ... }
  Favorites come first. The first entry after them carries a separator
  ("--- " prefix). Labels are kept unique ignoring case; a plugin present
  in VST and VST3 under the same label shows its format.
]]
function M.menu_entries(layout, root, reserved_names)
  local flat = {}
  for _, item in ipairs(layout.favorites) do
    flat[#flat + 1] = { label = item.section .. " - " .. item.label, format = item.format, path = item.path }
  end
  local favorite_count = #flat
  for _, section in ipairs(layout.sections) do
    for _, item in ipairs(section.items) do
      if not item.favorite then
        flat[#flat + 1] = { label = item.section .. " - " .. item.label, format = item.format, path = item.path }
      end
    end
  end

  make_labels_unique(flat)

  local used = {}
  for _, name in ipairs(reserved_names or {}) do
    used[name:lower()] = true
  end

  local entries = {}
  for index, item in ipairs(flat) do
    local label = item.label
    local n = 1
    while used[label:lower()] do
      n = n + 1
      label = item.label .. " (" .. n .. ")"
    end
    used[label:lower()] = true
    local name = root .. ":" .. label
    if index == favorite_count + 1 and favorite_count > 0 then
      name = "--- " .. name
    end
    entries[#entries + 1] = { name = name, path = item.path, label = label }
  end
  return entries
end

return M
