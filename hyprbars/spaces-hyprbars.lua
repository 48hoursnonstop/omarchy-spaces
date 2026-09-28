-- tornikegomareli.spaces managed Hyprbars config v1
-- Optional titlebar polish. The taskbar itself does not depend on Hyprbars.

local home = os.getenv("HOME") or ""
local xdg_data = os.getenv("XDG_DATA_HOME") or (home .. "/.local/share")
local xdg_config = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
local action_helper = xdg_data .. "/tornikegomareli.spaces/bin/spaces-hyprbars-action"
local override_path = xdg_config .. "/tornikegomareli.spaces/hyprbars-overrides.lua"

-- hyprpm plugins are loaded after the first config pass on a fresh session.
-- The official Hyprbars plugin reloads Hyprland config when it initializes,
-- so this guard keeps the pre-plugin pass error-free and the second pass applies
-- our options/buttons.
if hl and hl.on and hl.exec_cmd then
  hl.on("hyprland.start", function()
    hl.exec_cmd("hyprpm reload")
  end)
end

if not (hl and hl.plugin and hl.plugin.hyprbars) then
  return
end

local colors = {
  background = "101315",
  foreground = "cacccc",
  accent = "cacccc",
  muted = "707880",
  urgent = "a55555",
}

local function normalize_hex(value)
  local v = tostring(value or ""):gsub("#", "")
  if v:match("^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$") then
    return v
  end
  return nil
end

local function load_omarchy_colors()
  local path = home .. "/.local/state/omarchy/current/theme/colors.toml"
  local file = io.open(path, "r")
  if not file then return end

  -- Mirror Omarchy 4.0.4 Color.qml precedence instead of depending on the
  -- ordering of keys inside colors.toml. Explicit semantic roles win; legacy
  -- colorN entries are fallbacks only.
  local found_accent = false
  local found_muted = false
  local loaded_background = false
  local loaded_foreground = false
  local color0 = nil
  local color4 = nil
  local color7 = nil
  local color8 = nil

  for line in file:lines() do
    local key, value = line:match("^%s*([A-Za-z0-9_-]+)%s*=%s*[\"']?(#[0-9A-Fa-f]+)")
    local hex = normalize_hex(value)
    if key and hex then
      if key == "background" then
        colors.background = hex
        loaded_background = true
      elseif key == "foreground" then
        colors.foreground = hex
        loaded_foreground = true
      elseif key == "accent" then
        colors.accent = hex
        found_accent = true
      elseif key == "muted" then
        colors.muted = hex
        found_muted = true
      elseif key == "color0" then
        color0 = hex
      elseif key == "color4" then
        color4 = hex
      elseif key == "color7" then
        color7 = hex
      elseif key == "color8" then
        color8 = hex
      elseif key == "red" or key == "color1" then
        colors.urgent = hex
      end
    end
  end

  file:close()

  if not loaded_background and color0 then colors.background = color0 end
  if not loaded_foreground and color7 then colors.foreground = color7 end
  if not found_accent and color4 then colors.accent = color4 end
  if not found_muted and color8 then colors.muted = color8 end
end

local function rgb(hex)
  return "rgb(" .. hex .. ")"
end

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

load_omarchy_colors()

hl.config({
  plugin = {
    hyprbars = {
      enabled = true,
      bar_height = 26,
      bar_color = rgb(colors.background),
      col = {
        text = rgb(colors.foreground),
      },
      bar_title_enabled = true,
      bar_text_size = 11,
      bar_text_weight = 500,
      bar_text_font = "Sans",
      bar_text_align = "left",
      bar_buttons_alignment = "right",
      bar_part_of_window = true,
      bar_precedence_over_border = false,
      bar_padding = 8,
      bar_button_padding = 5,
      icon_on_hover = false,
      inactive_button_color = rgb(colors.muted),
      on_double_click = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
    },
  },
})

-- Hyprbars focuses the titlebar's exact window before running a button action.
-- Minimize is delegated to our state-safe backend through the helper; close uses
-- the reviewed Hyprland Lua dispatcher on that now-active window.
hl.plugin.hyprbars.add_button({
  bg_color = rgb(colors.urgent),
  fg_color = rgb(colors.background),
  size = 14,
  icon = "×",
  action = shell_quote(action_helper) .. " close",
})

hl.plugin.hyprbars.add_button({
  bg_color = rgb(colors.accent),
  fg_color = rgb(colors.background),
  size = 14,
  icon = "□",
  action = shell_quote(action_helper) .. " maximize",
})

hl.plugin.hyprbars.add_button({
  bg_color = rgb(colors.muted),
  fg_color = rgb(colors.foreground),
  size = 14,
  icon = "−",
  action = shell_quote(action_helper) .. " minimize",
})

-- Keep inactive titlebars visually quieter without inventing a second theme.
-- Hyprland 0.56 re-evaluates the `focus` match dynamically, and Hyprbars
-- exposes title color as a dynamic window-rule effect.
hl.window_rule({
  name = "tornikegomareli.spaces-hyprbar-active",
  match = { focus = true },
  ["hyprbars:title_color"] = rgb(colors.foreground),
})

hl.window_rule({
  name = "tornikegomareli.spaces-hyprbar-inactive",
  match = { focus = false },
  ["hyprbars:title_color"] = rgb(colors.muted),
})

-- Real fullscreen is distinct from Hyprland's maximized mode in 0.56.x, so
-- maximizing keeps the titlebar while true fullscreen removes its decoration.
hl.window_rule({
  name = "tornikegomareli.spaces-no-hyprbar-fullscreen",
  match = { fullscreen = true },
  ["hyprbars:no_bar"] = true,
})

-- Apps that advertise the Wayland content type `game` should not pay for
-- desktop titlebar chrome. Games that do not advertise it can still be
-- excluded explicitly through hyprbars-overrides.lua.
hl.window_rule({
  name = "tornikegomareli.spaces-no-hyprbar-game",
  match = { content = "^game$" },
  ["hyprbars:no_bar"] = true,
})

-- Optional user-owned additions/exclusions. This file is never created,
-- overwritten, or removed by the plugin.
local override = io.open(override_path, "r")
if override then
  override:close()
  dofile(override_path)
end
