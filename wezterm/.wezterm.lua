local wezterm = require 'wezterm'
local act = wezterm.action
local config = wezterm.config_builder()

config.color_scheme = 'Catppuccin Mocha'
config.ui_key_cap_rendering = 'Emacs'
-- Send raw Alt/Meta to the terminal instead of composed characters, on all
-- platforms. On Windows this also keeps AltGr (Right-Alt) from being
-- reported as Ctrl+Alt chords.
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

config.automatically_reload_config = true

config.font = wezterm.font_with_fallback {
  'JetBrains Mono',
  'Fira Code',
  'Cascadia Code',
  'Consolas',
  'Noto Color Emoji',
}
config.font_size = 13.0
config.line_height = 1.2

config.window_decorations = 'TITLE|RESIZE'
config.window_padding = { left = 8, right = 8, top = 8, bottom = 8 }
config.window_background_opacity = 0.95
config.initial_cols = 120
config.initial_rows = 32

config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true

config.default_cursor_style = 'BlinkingBar'
config.cursor_blink_rate = 500

config.front_end = 'WebGpu'
config.max_fps = 120
config.scrollback_lines = 50000
config.audible_bell = 'Disabled'

config.key_tables = {
  copy_mode = {
    { key = 'f', mods = 'CTRL', action = act.CopyMode 'MoveRight' },
    { key = 'b', mods = 'CTRL', action = act.CopyMode 'MoveLeft' },
    { key = 'n', mods = 'CTRL', action = act.CopyMode 'MoveDown' },
    { key = 'p', mods = 'CTRL', action = act.CopyMode 'MoveUp' },
    { key = 'a', mods = 'CTRL', action = act.CopyMode 'MoveToStartOfLine' },
    { key = 'e', mods = 'CTRL', action = act.CopyMode 'MoveToEndOfLineContent' },
    { key = 'v', mods = 'CTRL', action = act.CopyMode 'PageDown' },
    { key = 'v', mods = 'ALT',  action = act.CopyMode 'PageUp' },
    { key = '<', mods = 'ALT',  action = act.CopyMode 'MoveToScrollbackTop' },
    { key = '>', mods = 'ALT',  action = act.CopyMode 'MoveToScrollbackBottom' },
    { key = 'f', mods = 'ALT', action = act.CopyMode 'MoveForwardWord' },
    { key = 'b', mods = 'ALT', action = act.CopyMode 'MoveBackwardWord' },
    { key = 'd', mods = 'ALT', action = act.CopyMode 'MoveForwardWordEnd' },
    { key = 'Space', mods = 'CTRL', action = act.CopyMode { SetSelectionMode = 'Cell' } },
    { key = 'w',     mods = 'ALT',  action = act.CopyMode { SetSelectionMode = 'Word' } },
    { key = 'l',     mods = 'CTRL', action = act.CopyMode { SetSelectionMode = 'Line' } },
    { key = 'w', mods = 'CTRL', action = act.Multiple {
      { CopyTo = 'ClipboardAndPrimarySelection' },
      { CopyMode = 'Close' },
    }},
    { key = 'y', mods = 'CTRL', action = act.Multiple {
      { CopyTo = 'ClipboardAndPrimarySelection' },
      { CopyMode = 'Close' },
    }},
    { key = 'g', mods = 'CTRL', action = { CopyMode = 'Close' } },
    { key = 'Escape', mods = 'NONE', action = { CopyMode = 'Close' } },
    { key = 's', mods = 'CTRL', action = act.Search { CaseInSensitiveString = '' } },
    { key = 'r', mods = 'CTRL', action = act.Search { CaseInSensitiveString = '' } },
    { key = 'Home',  mods = 'NONE', action = act.CopyMode 'MoveToStartOfLine' },
    { key = 'End',   mods = 'NONE', action = act.CopyMode 'MoveToEndOfLineContent' },
    { key = 'LeftArrow',  mods = 'NONE', action = act.CopyMode 'MoveLeft' },
    { key = 'RightArrow', mods = 'NONE', action = act.CopyMode 'MoveRight' },
    { key = 'UpArrow',    mods = 'NONE', action = act.CopyMode 'MoveUp' },
    { key = 'DownArrow',  mods = 'NONE', action = act.CopyMode 'MoveDown' },
  },
  search_mode = {
    { key = 'Enter',  mods = 'NONE', action = act.CopyMode 'PriorMatch' },
    { key = 'Escape', mods = 'NONE', action = act.CopyMode 'Close' },
    { key = 'g', mods = 'CTRL', action = act.CopyMode 'Close' },
    { key = 'n', mods = 'CTRL', action = act.CopyMode 'NextMatch' },
    { key = 's', mods = 'CTRL', action = act.CopyMode 'NextMatch' },
    { key = 'p', mods = 'CTRL', action = act.CopyMode 'PriorMatch' },
    { key = 'r', mods = 'CTRL', action = act.CopyMode 'CycleMatchType' },
    { key = 'u', mods = 'CTRL', action = act.CopyMode 'ClearPattern' },
  },
}

config.keys = {
  { key = 'Space', mods = 'CTRL|SHIFT', action = act.ActivateCopyMode },
  { key = 'y', mods = 'CTRL', action = act.PasteFrom 'Clipboard' },
  { key = 'c', mods = 'CTRL|SHIFT', action = act.CopyTo 'Clipboard' },
  { key = 's', mods = 'CTRL|SHIFT', action = act.Search { CaseInSensitiveString = '' } },
  { key = 'p', mods = 'CTRL|SHIFT', action = act.ActivateCommandPalette },
  { key = 't', mods = 'CTRL|SHIFT', action = act.SpawnTab 'CurrentPaneDomain' },
  { key = 'w', mods = 'CTRL|SHIFT', action = act.CloseCurrentTab { confirm = false } },
  { key = 'Tab', mods = 'CTRL', action = act.ActivateTabRelative(1) },
  { key = 'Tab', mods = 'CTRL|SHIFT', action = act.ActivateTabRelative(-1) },
  { key = '2', mods = 'CTRL|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = '3', mods = 'CTRL|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 'LeftArrow',  mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Left' },
  { key = 'RightArrow', mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Right' },
  { key = 'UpArrow',    mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Up' },
  { key = 'DownArrow',  mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Down' },
  { key = '=', mods = 'CTRL|SHIFT', action = act.IncreaseFontSize },
  { key = '-', mods = 'CTRL|SHIFT', action = act.DecreaseFontSize },
  { key = '0', mods = 'CTRL|SHIFT', action = act.ResetFontSize },
  { key = 'F11', mods = 'NONE', action = act.ToggleFullScreen },
  { key = 'l', mods = 'CTRL', action = act.SendKey { key = 'l', mods = 'CTRL' } },
  { key = 'Space', mods = 'CTRL|ALT', action = act.QuickSelect },
  { key = 'o', mods = 'CTRL|SHIFT', action = act.QuickSelectArgs {
    label = 'open url',
    patterns = { 'https?://\\S+' },
    action = wezterm.action_callback(function(window, pane)
      local url = window:get_selection_text_for_pane(pane)
      wezterm.open_with(url)
    end),
  }},
  { key = 'f', mods = 'CTRL|SHIFT', action = act.QuickSelectArgs {
    label = 'pick path / ip / sha',
    patterns = {
      '[\\w.-]+/[\\w./-]+',           -- file paths
      '\\b\\d{1,3}(\\.\\d{1,3}){3}\\b', -- ipv4
      '\\b[0-9a-f]{7,40}\\b',         -- git sha
    },
  }},
}

config.mouse_bindings = {
  {
    event = { Down = { streak = 1, button = 'Right' } },
    mods = 'NONE',
    action = act.PasteFrom 'Clipboard',
  },
  {
    event = { Down = { streak = 1, button = 'Middle' } },
    mods = 'NONE',
    action = act.PasteFrom 'PrimarySelection',
  },
  -- Release-select copies straight to the clipboard (Emacs style)
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'NONE',
    action = act.CompleteSelection 'Clipboard',
  },
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'CTRL',
    action = act.CompleteSelection 'Clipboard',
  },
}

if wezterm.target_triple == 'x86_64-pc-windows-msvc' then
  -- Prefer MSYS2 zsh (installed by the dotfiles zsh module); fall back to
  -- pwsh when MSYS2 is absent. On Windows, PSReadLine defaults to "Windows"
  -- edit mode, so Emacs keys like Ctrl+B are unbound and get inserted as
  -- literal ^B; force Emacs mode at startup for the pwsh fallback.
  if wezterm.glob('C:\\msys64\\usr\\bin\\zsh.exe')[1] then
    config.default_prog = { 'C:\\msys64\\usr\\bin\\zsh.exe', '-l' }
  else
    config.default_prog = { 'pwsh.exe', '-NoLogo', '-NoExit', '-Command', 'Set-PSReadLineOption -EditMode Emacs' }
  end
  config.win32_system_backdrop = 'Acrylic'
elseif wezterm.target_triple == 'x86_64-apple-darwin'
  or wezterm.target_triple == 'aarch64-apple-darwin' then
  config.macos_window_background_blur = 30
  config.font = wezterm.font_with_fallback {
    { family = 'JetBrains Mono', weight = 'Bold' },
    'Fira Code',
    'Cascadia Code',
    'Consolas',
    'Noto Color Emoji',
  }
  table.insert(config.keys, { key = 'c', mods = 'SUPER', action = act.CopyTo 'Clipboard' })
  table.insert(config.keys, { key = 'v', mods = 'SUPER', action = act.PasteFrom 'Clipboard' })
  table.insert(config.keys, { key = 't', mods = 'SUPER', action = act.SpawnTab 'CurrentPaneDomain' })
end

wezterm.on('update-right-status', function(window, pane)
  local status = ''
  local key_table = window:active_key_table()
  if key_table then
    status = ' ' .. key_table .. ' '
  end
  for _, b in ipairs(wezterm.battery_info()) do
    status = status .. string.format(' %.0f%%', b.state_of_charge * 100)
  end
  window:set_right_status(status)
end)

config.window_close_confirmation = 'AlwaysPrompt'
config.exit_behavior = 'Close'

-- Machine-local overrides: ~/.wezterm.lua.local (created by install.sh,
-- not tracked). The file runs as a Lua chunk with `config` and `wezterm`
-- in scope, so lines like config.default_prog = { ... } override the
-- shared setup on this machine.
local local_file = wezterm.home_dir .. '/.wezterm.lua.local'
local f = io.open(local_file, 'r')
if f then
  local src = f:read('*a')
  f:close()
  local chunk = load(src, local_file, 't', { config = config, wezterm = wezterm })
  if chunk then
    local ok, err = pcall(chunk)
    if not ok then
      wezterm.log_error('.wezterm.lua.local error: ' .. tostring(err))
    end
  end
end

return config



