---Helper functions to parse different colour formats
--@module colorizer.color
local api = vim.api

local bit = require "bit"
local floor, min, max = math.floor, math.min, math.max
local band, rshift, lshift, tohex = bit.band, bit.rshift, bit.lshift, bit.tohex

local Trie = require "colorizer.trie"

local utils = require "colorizer.utils"
local byte_is_alphanumeric = utils.byte_is_alphanumeric
local byte_is_hex = utils.byte_is_hex
local byte_is_valid_colorchar = utils.byte_is_valid_colorchar
local count = utils.count
local parse_hex = utils.parse_hex

local color = {}

local ARGB_MINIMUM_LENGTH = #"0xAARRGGBB" - 1
---parse for 0xaarrggbb and return rgb hex.
-- a format used in android apps
---@param line string: line to parse
---@param i number: index of line from where to start parsing
---@return number|nil: index of line where the hex value ended
---@return string|nil: rgb hex value
function color.argb_hex_parser(line, i)
  if #line < i + ARGB_MINIMUM_LENGTH then
    return
  end

  local j = i + 2

  local n = j + 8
  local alpha
  local v = 0
  while j <= min(n, #line) do
    local b = line:byte(j)
    if not byte_is_hex(b) then
      break
    end
    if j - i <= 3 then
      alpha = parse_hex(b) + lshift(alpha or 0, 4)
    else
      v = parse_hex(b) + lshift(v, 4)
    end
    j = j + 1
  end
  if #line >= j and byte_is_alphanumeric(line:byte(j)) then
    return
  end
  local length = j - i
  if length ~= 10 then
    return
  end
  alpha = tonumber(alpha) / 255
  local r = floor(band(rshift(v, 16), 0xFF) * alpha)
  local g = floor(band(rshift(v, 8), 0xFF) * alpha)
  local b = floor(band(v, 0xFF) * alpha)
  local rgb_hex = string.format("%02x%02x%02x", r, g, b)
  return length, rgb_hex
end

--- Converts an HSL color value to RGB.
---@param h number: Hue
---@param s number: Saturation
---@param l number: Lightness
---@return number|nil,number|nil,number|nil
function color.hsl_to_rgb(h, s, l)
  if h > 1 or s > 1 or l > 1 then
    return
  end
  if s == 0 then
    local r = l * 255
    return r, r, r
  end
  local q
  if l < 0.5 then
    q = l * (1 + s)
  else
    q = l + s - l * s
  end
  local p = 2 * l - q
  return 255 * color.hue_to_rgb(p, q, h + 1 / 3),
    255 * color.hue_to_rgb(p, q, h),
    255 * color.hue_to_rgb(p, q, h - 1 / 3)
end

local CSS_HSLA_FN_MINIMUM_LENGTH = #"hsla(0,0%,0%)" - 1
local CSS_HSL_FN_MINIMUM_LENGTH = #"hsl(0,0%,0%)" - 1
---Parse for hsl() hsla() css function and return rgb hex.
-- For more info: https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/hsl
---@param line string: Line to parse
---@param i number: Index of line from where to start parsing
---@param opts table: Values passed from matchers like prefix
---@return number|nil: Index of line where the hsla/hsl function ended
---@return string|nil: rgb hex value
function color.hsl_function_parser(line, i, opts)
  local min_len = CSS_HSLA_FN_MINIMUM_LENGTH
  local min_commas, min_spaces = 2, 2
  local pattern = "^"
    .. opts.prefix
    .. "%(%s*([.%d]+)([deg]*)([turn]*)(%s?)%s*(,?)%s*(%d+)%%(%s?)%s*(,?)%s*(%d+)%%%s*(/?,?)%s*([.%d]*)([%%]?)%s*%)()"

  if opts.prefix == "hsl" then
    min_len = CSS_HSL_FN_MINIMUM_LENGTH
  end

  if #line < i + min_len then
    return
  end

  local h, deg, turn, ssep1, csep1, s, ssep2, csep2, l, sep3, a, percent_sign, match_end = line:sub(i):match(pattern)
  if not match_end then
    return
  end
  if a == "" then
    a = nil
  else
    min_commas = min_commas + 1
  end

  -- the text after hue should be either deg or empty
  if not ((deg == "") or (deg == "deg") or (turn == "turn")) then
    return
  end

  local c_seps = ("%s%s%s"):format(csep1, csep2, sep3)
  local s_seps = ("%s%s"):format(ssep1, ssep2)
  -- comma separator syntax
  if c_seps:match "," then
    if not (count(c_seps, ",") == min_commas) then
      return
    end
    -- space separator syntax with decimal or percentage alpha
  elseif count(s_seps, "%s") >= min_spaces then
    if a then
      if not (c_seps == "/") then
        return
      end
    end
  else
    return
  end

  if not a then
    a = 1
  else
    a = tonumber(a)
    -- if percentage, then convert to decimal
    if percent_sign == "%" then
      a = a / 100
    end
    -- although alpha doesn't support larger values than 1, css anyways renders it at 1
    if a > 1 then
      a = 1
    end
  end

  h = tonumber(h) or 1
  -- single turn is 360
  if turn == "turn" then
    h = 360 * h
  end

  -- if hue angle if greater than 360, then calculate the hue within 360
  if h > 360 then
    local turns = h / 360
    h = 360 * (turns - floor(turns))
  end

  -- if saturation or luminance percentage is  greater than 100 then reset it to 100
  s = tonumber(s)
  if s > 100 then
    s = 100
  end
  l = tonumber(l)
  if l > 100 then
    l = 100
  end

  local r, g, b = color.hsl_to_rgb(h / 360, s / 100, l / 100)
  if r == nil or g == nil or b == nil then
    return
  end
  local rgb_hex = string.format("%02x%02x%02x", r * a, g * a, b * a)
  return match_end - 1, rgb_hex
end

---Convert hsl colour values to rgb.
-- Source: https://gist.github.com/mjackson/5311256
---@param p number
---@param q number
---@param t number
---@return number
function color.hue_to_rgb(p, q, t)
  if t < 0 then
    t = t + 1
  end
  if t > 1 then
    t = t - 1
  end
  if t < 1 / 6 then
    return p + (q - p) * 6 * t
  end
  if t < 1 / 2 then
    return q
  end
  if t < 2 / 3 then
    return p + (q - p) * (2 / 3 - t) * 6
  end
  return p
end

---Determine whether to use black or white text.
--
-- ref: https://stackoverflow.com/a/1855903/837964
-- https://stackoverflow.com/questions/596216/formula-to-determine-brightness-of-rgb-color
---@param r number: Red
---@param g number: Green
---@param b number: Blue
function color.is_bright(r, g, b)
  -- counting the perceptive luminance - human eye favors green color
  local luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
  if luminance > 0.5 then
    return true -- bright colors, black font
  else
    return false -- dark colors, white font
  end
end

local COLOR_MAP
local COLOR_TRIE
local COLOR_NAME_MINLEN, COLOR_NAME_MAXLEN
local COLOR_NAME_SETTINGS = { lowercase = true, strip_digits = false }
local TAILWIND_ENABLED = false
--- Grab all the colour values from `vim.api.nvim_get_color_map` and create a lookup table.
-- COLOR_MAP is used to store the colour values
---@param line string: Line to parse
---@param i number: Index of line from where to start parsing
---@param opts table: Currently contains whether tailwind is enabled or not
function color.name_parser(line, i, opts)
  --- Setup the COLOR_MAP and COLOR_TRIE
  if not COLOR_TRIE or opts.tailwind ~= TAILWIND_ENABLED then
    COLOR_MAP = {}
    COLOR_TRIE = Trie()
    for k, v in pairs(api.nvim_get_color_map()) do
      if not (COLOR_NAME_SETTINGS.strip_digits and k:match "%d+$") then
        COLOR_NAME_MINLEN = COLOR_NAME_MINLEN and min(#k, COLOR_NAME_MINLEN) or #k
        COLOR_NAME_MAXLEN = COLOR_NAME_MAXLEN and max(#k, COLOR_NAME_MAXLEN) or #k
        local rgb_hex = tohex(v, 6)
        COLOR_MAP[k] = rgb_hex
        COLOR_TRIE:insert(k)
        if COLOR_NAME_SETTINGS.lowercase then
          local lowercase = k:lower()
          COLOR_MAP[lowercase] = rgb_hex
          COLOR_TRIE:insert(lowercase)
        end
      end
    end
    if opts and opts.tailwind then
      if opts.tailwind == true or opts.tailwind == "normal" or opts.tailwind == "both" then
        local tailwind = require "colorizer.tailwind_colors"
        -- setup tailwind colors
        for k, v in pairs(tailwind.colors) do
          for _, pre in ipairs(tailwind.prefixes) do
            local name = pre .. "-" .. k
            COLOR_NAME_MINLEN = COLOR_NAME_MINLEN and min(#name, COLOR_NAME_MINLEN) or #name
            COLOR_NAME_MAXLEN = COLOR_NAME_MAXLEN and max(#name, COLOR_NAME_MAXLEN) or #name
            COLOR_MAP[name] = v
            COLOR_TRIE:insert(name)
          end
        end
      end
    end
    TAILWIND_ENABLED = opts.tailwind
  end

  if #line < i + COLOR_NAME_MINLEN - 1 then
    return
  end

  if i > 1 and byte_is_valid_colorchar(line:byte(i - 1)) then
    return
  end

  local prefix = COLOR_TRIE:longest_prefix(line, i)
  if prefix then
    -- Check if there is a letter here so as to disallow matching here.
    -- Take the Blue out of Blueberry
    -- Line end or non-letter.
    local next_byte_index = i + #prefix
    if #line >= next_byte_index and byte_is_valid_colorchar(line:byte(next_byte_index)) then
      return
    end
    return #prefix, COLOR_MAP[prefix]
  end
end

local CSS_RGBA_FN_MINIMUM_LENGTH = #"rgba(0,0,0)" - 1
local CSS_RGB_FN_MINIMUM_LENGTH = #"rgb(0,0,0)" - 1
---Parse for rgb() rgba() css function and return rgb hex.
-- For more info: https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/rgb
---@param line string: Line to parse
---@param i number: Index of line from where to start parsing
---@param opts table: Values passed from matchers like prefix
---@return number|nil: Index of line where the rgb/rgba function ended
---@return string|nil: rgb hex value
function color.rgb_function_parser(line, i, opts)
  local min_len = CSS_RGBA_FN_MINIMUM_LENGTH
  local min_commas, min_spaces, min_percent = 2, 2, 3
  local pattern = "^"
    .. opts.prefix
    .. "%(%s*([.%d]+)([%%]?)(%s?)%s*(,?)%s*([.%d]+)([%%]?)(%s?)%s*(,?)%s*([.%d]+)([%%]?)%s*(/?,?)%s*([.%d]*)([%%]?)%s*%)()"

  if opts.prefix == "rgb" then
    min_len = CSS_RGB_FN_MINIMUM_LENGTH
  end

  if #line < i + min_len then
    return
  end

  local r, unit1, ssep1, csep1, g, unit2, ssep2, csep2, b, unit3, sep3, a, unit_a, match_end =
    line:sub(i):match(pattern)
  if not match_end then
    return
  end

  if a == "" then
    a = nil
  else
    min_commas = min_commas + 1
  end

  local units = ("%s%s%s"):format(unit1, unit2, unit3)
  if units:match "%%" then
    if not ((count(units, "%%")) == min_percent) then
      return
    end
  end

  local c_seps = ("%s%s%s"):format(csep1, csep2, sep3)
  local s_seps = ("%s%s"):format(ssep1, ssep2)
  -- comma separator syntax
  if c_seps:match "," then
    if not (count(c_seps, ",") == min_commas) then
      return
    end
    -- space separator syntax with decimal or percentage alpha
  elseif count(s_seps, "%s") >= min_spaces then
    if a then
      if not (c_seps == "/") then
        return
      end
    end
  else
    return
  end

  if not a then
    a = 1
  else
    a = tonumber(a)
    -- if percentage, then convert to decimal
    if unit_a == "%" then
      a = a / 100
    end
    -- although alpha doesn't support larger values than 1, css anyways renders it at 1
    if a > 1 then
      a = 1
    end
  end

  r = tonumber(r)
  if not r then
    return
  end
  g = tonumber(g)
  if not g then
    return
  end
  b = tonumber(b)
  if not b then
    return
  end

  if unit1 == "%" then
    r = r / 100 * 255
    g = g / 100 * 255
    b = b / 100 * 255
  else
    -- although r,g,b doesn't support larger values than 255, css anyways renders it at 255
    if r > 255 then
      r = 255
    end
    if g > 255 then
      g = 255
    end
    if b > 255 then
      b = 255
    end
  end

  local rgb_hex = string.format("%02x%02x%02x", r * a, g * a, b * a)
  return match_end - 1, rgb_hex
end

---parse for #rrggbbaa and return rgb hex.
-- a format used in android apps
---@param line string: line to parse
---@param i number: index of line from where to start parsing
---@param opts table: Containing minlen, maxlen, valid_lengths
---@return number|nil: index of line where the hex value ended
---@return string|nil: rgb hex value
function color.rgba_hex_parser(line, i, opts)
  local minlen, maxlen, valid_lengths = opts.minlen, opts.maxlen, opts.valid_lengths
  local j = i + 1
  if #line < j + minlen - 1 then
    return
  end

  if i > 1 and byte_is_alphanumeric(line:byte(i - 1)) then
    return
  end

  local n = j + maxlen
  local alpha
  local v = 0

  while j <= min(n, #line) do
    local b = line:byte(j)
    if not byte_is_hex(b) then
      break
    end
    if j - i >= 7 then
      alpha = parse_hex(b) + lshift(alpha or 0, 4)
    else
      v = parse_hex(b) + lshift(v, 4)
    end
    j = j + 1
  end

  if #line >= j and byte_is_alphanumeric(line:byte(j)) then
    return
  end

  local length = j - i
  if length ~= 4 and length ~= 7 and length ~= 9 then
    return
  end

  if alpha then
    alpha = tonumber(alpha) / 255
    local r = floor(band(rshift(v, 16), 0xFF) * alpha)
    local g = floor(band(rshift(v, 8), 0xFF) * alpha)
    local b = floor(band(v, 0xFF) * alpha)
    local rgb_hex = string.format("%02x%02x%02x", r, g, b)
    return 9, rgb_hex
  end
  return (valid_lengths[length - 1] and length), line:sub(i + 1, i + length - 1)
end

return color
