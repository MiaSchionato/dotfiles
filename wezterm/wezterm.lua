-- =============================================================================
--  WezTerm  —  ported from MiaSchionato/dotfiles (foot + fish)
--  Theme:  TokyoNight Night   |   Shell: Nushell   |   Font: JetBrainsMono NF
-- =============================================================================
local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- ---- shell -----------------------------------------------------------------
-- foot.ini had `shell=fish`; the Windows port of that workflow is Nushell.
local nu = wezterm.home_dir .. "\\AppData\\Local\\Programs\\nu\\bin\\nu.exe"
config.default_prog = { nu }

-- ---- theme  (foot/themes/tokyonight_night.ini) ----------------------------
config.color_scheme = "Tokyo Night"
config.colors = {
  foreground = "#c0caf5",
  background = "#1a1b26",
  cursor_bg = "#c0caf5",
  cursor_fg = "#1a1b26",
  cursor_border = "#c0caf5",
  selection_fg = "#c0caf5",
  selection_bg = "#283457",
  ansi = { "#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6" },
  brights = { "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5" },
}

-- ---- font  (foot.ini: `font=monospace:size=20`) ---------------------------
-- foot ran at size 20 on a HiDPI Wayland setup; 16 is the equivalent here.
-- Bump this if you want it bigger.
config.font = wezterm.font_with_fallback({
  "JetBrainsMono Nerd Font",
  "JetBrains Mono",
  "Symbols Nerd Font Mono",
  "Consolas",
})
config.font_size = 16.0
config.line_height = 1.0
config.warn_about_missing_glyphs = false

-- ---- window --------------------------------------------------------------
config.window_padding = { left = 8, right = 8, top = 6, bottom = 4 }
config.window_background_opacity = 1.0
config.window_decorations = "RESIZE"
config.adjust_window_size_when_changing_font_size = false
config.enable_scroll_bar = false
config.scrollback_lines = 10000
config.audible_bell = "Disabled"
config.default_cursor_style = "SteadyBlock"
config.animation_fps = 1
config.cursor_blink_rate = 0

-- ---- tab bar  (minimal, like a bare foot window) ------------------------
config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = false
config.tab_max_width = 28
config.show_new_tab_button_in_tab_bar = false

-- ---- keys  (foot-style Ctrl+Shift bindings) ----------------------------
config.keys = {
  { key = "n", mods = "CTRL|SHIFT", action = wezterm.action.SpawnWindow },
  { key = "t", mods = "CTRL|SHIFT", action = wezterm.action.SpawnTab("CurrentPaneDomain") },
  { key = "w", mods = "CTRL|SHIFT", action = wezterm.action.CloseCurrentTab({ confirm = false }) },
  { key = "c", mods = "CTRL|SHIFT", action = wezterm.action.CopyTo("Clipboard") },
  { key = "v", mods = "CTRL|SHIFT", action = wezterm.action.PasteFrom("Clipboard") },
  { key = "r", mods = "CTRL|SHIFT", action = wezterm.action.Search({ CaseInSensitiveString = "" }) },
  { key = "=", mods = "CTRL",       action = wezterm.action.IncreaseFontSize },
  { key = "-", mods = "CTRL",       action = wezterm.action.DecreaseFontSize },
  { key = "0", mods = "CTRL",       action = wezterm.action.ResetFontSize },
  -- pane splits (tmux-ish, since the Linux setup auto-attached tmux)
  { key = "|", mods = "CTRL|SHIFT", action = wezterm.action.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  { key = "-", mods = "CTRL|SHIFT", action = wezterm.action.SplitVertical({ domain = "CurrentPaneDomain" }) },
  { key = "h", mods = "CTRL|SHIFT", action = wezterm.action.ActivatePaneDirection("Left") },
  { key = "l", mods = "CTRL|SHIFT", action = wezterm.action.ActivatePaneDirection("Right") },
  { key = "k", mods = "CTRL|SHIFT", action = wezterm.action.ActivatePaneDirection("Up") },
  { key = "j", mods = "CTRL|SHIFT", action = wezterm.action.ActivatePaneDirection("Down") },
}

return config
