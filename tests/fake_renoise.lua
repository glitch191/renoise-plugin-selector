--[[
  Minimal fake of the parts of the Renoise scripting API used by main.lua.
  For offline tests only: it records menu entries, errors and plugin loads.
]]

local M = {}

function M.install(infos)
  local env = {
    entries = {},
    order = {},
    errors = {},
    warnings = {},
    messages = {},
    notifiers = {},
    bundle_path = (os.getenv("TEMP") or os.getenv("TMPDIR") or ".") .. "/",
  }

  local current_infos = infos
  local has_song = true

  local instrument = { cleared = 0, loaded_path = nil, load_result = true }
  env.instrument = instrument

  function instrument:clear()
    self.cleared = self.cleared + 1
  end

  instrument.plugin_properties = {}
  setmetatable(instrument.plugin_properties, {
    __index = function(_, key)
      if key == "available_plugin_infos" then
        return current_infos
      elseif key == "load_plugin" then
        return function(_, path)
          if instrument.load_result == "raise" then
            error("fake load failure")
          end
          instrument.loaded_path = path
          return instrument.load_result
        end
      end
    end,
  })

  local song = { selected_instrument = instrument }

  local function observable(name)
    return {
      add_notifier = function(_, fn)
        env.notifiers[name] = env.notifiers[name] or {}
        table.insert(env.notifiers[name], fn)
      end,
    }
  end

  local tool = {
    bundle_path = env.bundle_path,
    tool_finished_loading_observable = observable("tool_finished_loading_observable"),
    app_new_document_observable = observable("app_new_document_observable"),
  }

  function tool:has_menu_entry(name)
    return env.entries[name] ~= nil
  end

  function tool:add_menu_entry(entry)
    assert(env.entries[entry.name] == nil, "menu entry already exists: " .. entry.name)
    env.entries[entry.name] = entry
    table.insert(env.order, entry.name)
  end

  function tool:remove_menu_entry(name)
    assert(env.entries[name] ~= nil, "menu entry does not exist: " .. name)
    env.entries[name] = nil
    for i, n in ipairs(env.order) do
      if n == name then
        table.remove(env.order, i)
        break
      end
    end
  end

  local app = {}
  function app:show_error(text) table.insert(env.errors, text) end
  function app:show_warning(text) table.insert(env.warnings, text) end
  function app:show_message(text) table.insert(env.messages, text) end

  renoise = {
    API_VERSION = 6.2,
    RENOISE_VERSION = "3.5.4 (fake)",
    tool = function() return tool end,
    app = function() return app end,
    song = function() return has_song and song or nil end,
  }

  function env.fire(name)
    for _, fn in ipairs(env.notifiers[name] or {}) do
      fn()
    end
  end

  function env.entry_count()
    return #env.order
  end

  function env.entry_names()
    local copy = {}
    for i, n in ipairs(env.order) do copy[i] = n end
    return copy
  end

  function env.set_infos(list)
    current_infos = list
  end

  function env.set_song(value)
    has_song = value
  end

  return env
end

return M
