--[[
  grouping.lua

  Pure Lua logic (no Renoise API calls) that turns the list returned by
  renoise.InstrumentPluginProperties.available_plugin_infos into a short
  menu layout:

    Load Plugin > favorite plugins (directly, at the top)
    Load Plugin > Vendor > Plugin (VST and VST3 mixed)

  Kept separate from main.lua so it can be tested outside of Renoise.

  Vendor detection: Renoise stores each plugin's display name as
  "Vendor: Plugin" (the same string it caches as DisplayName in its plugin
  database). The vendor is the text before the first ": ". Vendors are
  grouped by their exact name, without merging variants, as Renoise does.

  Sorting: Renoise sorts by character code, so uppercase names come before
  lowercase ones ("Waves" before "retro-chip-vst"). The same order is used
  here. Plugins without a vendor go to a final "Unknown" section.
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
  Build the menu layout from a list of plugin infos.

  Returns a table:
    {
      favorites = { item, ... },
      sections = {                       -- vendors sorted, Unknown last
        { name = "Vendor", items = { item, ... } }, ...
      },
      skipped = { { info = info, reason = "..." }, ... },
      plugin_count = <number of VST/VST3 instruments listed>,
    }
  Each item is { label = <menu label>, path = <original path>,
  format = "VST" | "VST3", vendor = <raw vendor>, name = <raw name> }.
  When one section holds the same plugin name twice (typically VST and
  VST3), the format is added to the label.
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

      section.items[#section.items + 1] = {
        label = M.sanitize(plugin_name),
        path = info.path,
        format = format,
        vendor = vendor,
        name = tostring(info.name or ""),
      }
      result.plugin_count = result.plugin_count + 1

      if M.truthy(info.is_favorite) then
        local favorite_label = info.favorite_name
        if type(favorite_label) ~= "string" or trim(favorite_label) == "" then
          favorite_label = plugin_name
        end
        result.favorites[#result.favorites + 1] = {
          label = M.sanitize(favorite_label),
          path = info.path,
          format = format,
          vendor = vendor,
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

  table.sort(result.favorites, compare_items)
  make_labels_unique(result.favorites)
  for _, section in ipairs(result.sections) do
    table.sort(section.items, compare_items)
    make_labels_unique(section.items)
  end

  return result
end

--[[
  Turn a layout into an ordered list of menu entries:
    { { name = "<root>:<label>" or "<root>:<vendor>:<label>", path = "...",
        label = "..." }, ... }
  Favorites come first, directly under the root. Full names are kept unique
  ignoring case, and a favorite never takes the name of a vendor submenu
  or of one of the tool's own entries.
]]
function M.menu_entries(layout, root, reserved_names)
  local entries = {}
  local used = {}

  for _, name in ipairs(reserved_names or {}) do
    used[(root .. ":" .. name):lower()] = true
  end
  for _, section in ipairs(layout.sections) do
    used[(root .. ":" .. section.name):lower()] = true
  end

  local function add(prefix, item)
    local name = prefix .. ":" .. item.label
    if used[name:lower()] then
      name = prefix .. ":" .. item.label .. " (" .. item.format .. ")"
    end
    local n = 1
    local base = name
    while used[name:lower()] do
      n = n + 1
      name = base .. " (" .. n .. ")"
    end
    used[name:lower()] = true
    entries[#entries + 1] = { name = name, path = item.path, label = item.label }
  end

  for _, item in ipairs(layout.favorites) do
    add(root, item)
  end
  for _, section in ipairs(layout.sections) do
    for _, item in ipairs(section.items) do
      add(root .. ":" .. section.name, item)
    end
  end
  return entries
end

return M
