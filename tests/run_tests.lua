--[[
  Offline tests for renoise-plugin-selector.

  Run from the repository root with a Lua 5.1 compatible interpreter:
    luajit tests/run_tests.lua

  All plugin names, vendors and paths below are FICTIONAL test data.
  main.lua is exercised through a minimal fake of the Renoise API
  (tests/fake_renoise.lua), not through Renoise itself.
]]

package.path = "./?.lua;./tests/?.lua;" .. package.path

local grouping = require("grouping")
local fake = require("fake_renoise")

local passed, failed = 0, 0

local function check(condition, message)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. message)
  end
end

local function eq(actual, expected, message)
  check(actual == expected,
    ("%s (expected %q, got %q)"):format(message, tostring(expected), tostring(actual)))
end

local function info(path, name, extra)
  -- Like Renoise's cache, short and favorite names have no vendor prefix.
  local _, plain = grouping.split_vendor(name)
  local t = { path = path, name = name, short_name = plain, favorite_name = plain,
              is_favorite = false, is_bridged = false }
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end

local function names(entries)
  local list = {}
  for _, e in ipairs(entries) do list[#list + 1] = e.name end
  return list
end

local function index_of(list, value)
  for i, v in ipairs(list) do
    if v == value then return i end
  end
  return nil
end

local ROOT = "Instrument Box:Load Plugin"

--------------------------------------------------------------------------------
print("-- sanitize, split_vendor, format_of")

eq(grouping.sanitize("Synth: Pro/Max\\X"), "Synth- Pro-Max-X", "colons and slashes replaced")
eq(grouping.sanitize("--- Lead"), "Lead", "leading dashes removed")
eq(grouping.sanitize("  a \t b  "), "a b", "whitespace collapsed")
eq(grouping.sanitize(""), "Unnamed", "empty name")
eq(grouping.sanitize("Caf\195\169 Synth"), "Caf\195\169 Synth", "UTF-8 kept")

local v, n = grouping.split_vendor("Fake Audio Co., Ltd.: Synth: Deluxe")
eq(v, "Fake Audio Co., Ltd.", "vendor before first ': '")
eq(n, "Synth: Deluxe", "rest is the plugin name")
v, n = grouping.split_vendor("NoVendorSynth")
eq(v, "", "no vendor")
eq(n, "NoVendorSynth", "name without vendor")

eq(grouping.format_of("Audio/Generators/VST3/0123ABCD"), "VST3", "VST3 path")
eq(grouping.format_of("Audio/Generators/VST/FakeSynth"), "VST", "VST path")
eq(grouping.format_of("Audio/Generators/AU/aumu:abcd"), nil, "AU path skipped")
eq(grouping.format_of("Audio/Generators/LADSPA/x"), nil, "other format skipped")
eq(grouping.format_of("Audio/Generators/AU/VST3"), nil, "plugin id is not a format")
eq(grouping.format_of(nil), nil, "nil path")

check(grouping.truthy(true) and grouping.truthy("true") and not grouping.truthy(false)
  and not grouping.truthy("false") and not grouping.truthy(nil), "truthy")

--------------------------------------------------------------------------------
print("-- grouping and order")

local infos = {
  info("Audio/Generators/VST3/A1", "Wavesmith: Electric Keys"),
  info("Audio/Generators/VST3/A2", "Wavesmith: Codex Pad"),
  info("Audio/Generators/VST3/A3", "retro-fake-vst: Retro Thing"),
  info("Audio/Generators/VST3/A4", "Dreamfake Co., Ltd.: Voice Studio"),
  info("Audio/Generators/VST3/A5", "Unknown Vendor: Mystery VST3"),
  info("Audio/Generators/VST/B1", "Wavesmith: Electric Keys"),
  info("Audio/Generators/VST/B2", "fakeaudio: Small Synth"),
  info("Audio/Generators/VST/B3", "FakeAudio: Big Synth"),
  info("Audio/Generators/VST/B4", "-: Dash Vendor Synth"),
  info("Audio/Generators/VST/B5", "NoVendorSynth"),
  info("Audio/Generators/VST/B6", "Slash/Vendor: Odd:Name", { is_favorite = "true", favorite_name = "Odd:Name" }),
  info("Audio/Generators/VST/B7", "Wavesmith: Twin"),
  info("Audio/Generators/VST/B8", "Wavesmith: Twin"),
  info("Audio/Generators/AU/C1", "Wavesmith: AU Only"),
  info("Audio/Generators/VST3/A6", "Bridgeco: Old Synth", { is_bridged = true, is_favorite = true }),
}

local layout = grouping.build(infos)
eq(layout.plugin_count, 14, "VST and VST3 plugins listed")
eq(#layout.skipped, 1, "AU plugin skipped")

local section_names = {}
for _, s in ipairs(layout.sections) do section_names[#section_names + 1] = s.name end
eq(table.concat(section_names, "|"),
  "Bridgeco|Dreamfake Co., Ltd.|FakeAudio|Slash-Vendor|Wavesmith|fakeaudio|retro-fake-vst|Unknown",
  "vendors exact, character-code order, Unknown last")
eq(#layout.sections[#layout.sections].items, 3, "'-', 'Unknown Vendor' and missing vendor go to Unknown")

local entries = grouping.menu_entries(layout, ROOT, { "Dump Plugin Info" })
local list = names(entries)
eq(table.concat(list, "\n"), table.concat({
  ROOT .. ":Bridgeco - Old Synth",
  ROOT .. ":Slash-Vendor - Odd-Name",
  "--- " .. ROOT .. ":Dreamfake Co., Ltd. - Voice Studio",
  ROOT .. ":FakeAudio - Big Synth",
  ROOT .. ":Wavesmith - Codex Pad",
  ROOT .. ":Wavesmith - Electric Keys (VST)",
  ROOT .. ":Wavesmith - Electric Keys (VST3)",
  ROOT .. ":Wavesmith - Twin",
  ROOT .. ":Wavesmith - Twin (2)",
  ROOT .. ":fakeaudio - Small Synth",
  ROOT .. ":retro-fake-vst - Retro Thing",
  ROOT .. ":Unknown - Dash Vendor Synth",
  ROOT .. ":Unknown - Mystery VST3",
  ROOT .. ":Unknown - NoVendorSynth",
}, "\n"), "flat list: favorites first, separator, then Vendor - Plugin, favorites not repeated")

for _, e in ipairs(entries) do
  if e.label == "Slash-Vendor - Odd-Name" then
    eq(e.path, "Audio/Generators/VST/B6", "original path kept for loading")
  end
end

local favorite_only = grouping.menu_entries(grouping.build({
  info("Audio/Generators/VST3/F1", "Vendor: Same", { is_favorite = true }),
  info("Audio/Generators/VST/F2", "Vendor: Same", { is_favorite = true }),
}), ROOT)
eq(favorite_only[1].name, ROOT .. ":Vendor - Same (VST)", "favorite duplicate shows VST")
eq(favorite_only[2].name, ROOT .. ":Vendor - Same (VST3)", "favorite duplicate shows VST3")

local no_favorites = grouping.menu_entries(grouping.build({
  info("Audio/Generators/VST/H1", "Vendor: Plain"),
}), ROOT)
eq(no_favorites[1].name, ROOT .. ":Vendor - Plain", "no separator without favorites")

eq(#grouping.menu_entries(grouping.build({}), ROOT), 0, "empty list")

--------------------------------------------------------------------------------
print("-- main.lua with the fake Renoise API")

local function fake_infos(count)
  local list = {}
  for i = 1, count do
    local format = (i % 3 == 0) and "VST3" or "VST"
    list[#list + 1] = info(
      ("Audio/Generators/%s/FakeId%04d"):format(format, i),
      ("Fake Vendor %02d: Fake Synth %04d"):format(i % 60, i),
      { is_favorite = (i % 50 == 0) })
  end
  return list
end

local env = fake.install(fake_infos(500))
local started = os.clock()
dofile("main.lua")
env.fire("tool_finished_loading_observable")
local elapsed = os.clock() - started
print(("   500 fake plugins: %d menu entries built in %.3f s"):format(env.entry_count(), elapsed))
check(elapsed < 1.0, "menu built in less than one second")
eq(env.entry_count(), 500 + 1, "500 plugins (favorites listed once) + dump entry")
local order = env.entry_names()
eq(order[#order], "--- " .. ROOT .. ":Dump Plugin Info", "dump entry last")
for i = 1, 10 do
  check(env.entries[order[i]] and order[i]:find(" - Fake Synth 0", 1, true) and
    tonumber(order[i]:match("(%d+)$")) % 50 == 0, "favorites first in the menu " .. i)
end
check(order[11]:find("--- ", 1, true) == 1, "separator after favorites")

env.fire("app_new_document_observable")
env.fire("app_new_document_observable")
eq(env.entry_count(), 501, "rebuild leaves no duplicates")

env.set_infos(fake_infos(20))
env.fire("app_new_document_observable")
eq(env.entry_count(), 20 + 0 + 1, "rebuild after a smaller scan leaves no orphan entries")
order = env.entry_names()
eq(order[#order], "--- " .. ROOT .. ":Dump Plugin Info", "dump entry still last")

-- Loading
local target
for _, name in ipairs(order) do
  if name == ROOT .. ":Fake Vendor 01 - Fake Synth 0001" then target = env.entries[name] end
end
target.invoke()
eq(env.instrument.cleared, 1, "instrument cleared before loading")
eq(env.instrument.loaded_path, "Audio/Generators/VST/FakeId0001", "plugin loaded with the original path")
eq(#env.errors, 0, "no error on successful load")

env.instrument.load_result = false
target.invoke()
eq(#env.errors, 1, "error shown when load_plugin returns false")
check(env.errors[1]:find("could not load", 1, true) ~= nil, "clear error message")

env.instrument.load_result = "raise"
target.invoke()
eq(#env.errors, 2, "error shown when load_plugin raises")

-- No song yet
env.set_song(false)
env.fire("tool_finished_loading_observable")
eq(#env.warnings, 0, "no warning when no song is loaded")
env.set_song(true)

-- Dump
env.entries["--- " .. ROOT .. ":Dump Plugin Info"].invoke()
local dump = io.open(env.bundle_path .. "plugin-info-dump.txt", "r")
check(dump ~= nil, "dump file written in the tool folder")
if dump then
  local text = dump:read("*a")
  dump:close()
  os.remove(env.bundle_path .. "plugin-info-dump.txt")
  check(text:find("== Raw available_plugin_infos ==", 1, true) ~= nil, "dump has raw section")
  check(text:find("favorite_name:", 1, true) ~= nil, "dump lists favorite_name")
  check(text:find("== Computed grouping ==", 1, true) ~= nil, "dump has grouping section")
end

--------------------------------------------------------------------------------
print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
