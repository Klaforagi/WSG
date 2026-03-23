--------------------------------------------------------------------------------
-- UITheme.lua  –  Centralized color & style constants for all KingsGround menus
-- Reference: TeamStatsUI / scoreboard deep-navy visual language.
--
-- Usage (from any SideUI sibling module):
--   local UITheme = require(script.Parent.UITheme)
--   local GOLD = UITheme.GOLD
--------------------------------------------------------------------------------

local UITheme = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- Core backgrounds
-- ═══════════════════════════════════════════════════════════════════════════
UITheme.NAVY         = Color3.fromRGB(12, 14, 28)       -- primary panel bg
UITheme.NAVY_LIGHT   = Color3.fromRGB(22, 26, 48)       -- secondary / button bg
UITheme.NAVY_MID     = Color3.fromRGB(16, 20, 40)       -- intermediate shade
UITheme.BLUE_BG      = Color3.fromRGB(16, 24, 56)       -- team section bg tint

-- ═══════════════════════════════════════════════════════════════════════════
-- Gold / accent
-- ═══════════════════════════════════════════════════════════════════════════
UITheme.GOLD         = Color3.fromRGB(255, 215, 80)      -- titles, primary accent
UITheme.GOLD_DIM     = Color3.fromRGB(180, 150, 50)      -- strokes, dividers
UITheme.GOLD_WARM    = Color3.fromRGB(255, 200, 40)      -- badges, glow

-- ═══════════════════════════════════════════════════════════════════════════
-- Cards & content
-- ═══════════════════════════════════════════════════════════════════════════
UITheme.CARD_BG      = Color3.fromRGB(26, 30, 48)        -- card / row bg
UITheme.CARD_STROKE  = Color3.fromRGB(55, 62, 95)        -- card border
UITheme.CARD_OWNED   = Color3.fromRGB(22, 38, 34)        -- owned / equipped / claimed
UITheme.CARD_HIGHLIGHT = Color3.fromRGB(36, 33, 18)      -- claimable / pending
UITheme.ICON_BG      = Color3.fromRGB(16, 18, 30)        -- icon well bg

-- ═══════════════════════════════════════════════════════════════════════════
-- Sidebar / tabs
-- ═══════════════════════════════════════════════════════════════════════════
UITheme.SIDEBAR_BG   = Color3.fromRGB(18, 20, 34)        -- tab rail bg
UITheme.TAB_ACTIVE   = Color3.fromRGB(32, 30, 18)        -- active tab tint
UITheme.TAB_HOVER    = Color3.fromRGB(28, 26, 18)        -- tab hover tint

-- ═══════════════════════════════════════════════════════════════════════════
-- Text
-- ═══════════════════════════════════════════════════════════════════════════
UITheme.WHITE        = Color3.fromRGB(245, 245, 252)      -- primary text
UITheme.DIM_TEXT     = Color3.fromRGB(145, 150, 175)      -- secondary / muted text
UITheme.GRAY         = Color3.fromRGB(140, 140, 155)      -- column headers

-- ═══════════════════════════════════════════════════════════════════════════
-- Buttons
-- ═══════════════════════════════════════════════════════════════════════════
UITheme.BTN_BG       = Color3.fromRGB(48, 55, 82)         -- standard button bg
UITheme.BTN_STROKE   = Color3.fromRGB(90, 100, 140)       -- standard button stroke
UITheme.GREEN_BTN    = Color3.fromRGB(35, 190, 75)        -- positive / confirm
UITheme.GREEN_GLOW   = Color3.fromRGB(50, 230, 110)       -- success glow
UITheme.RED_TEXT     = Color3.fromRGB(255, 80, 80)         -- error / negative
UITheme.RED_BTN     = Color3.fromRGB(160, 50, 50)          -- destructive btn
UITheme.DISABLED_BG  = Color3.fromRGB(35, 38, 52)         -- disabled / locked

-- ═══════════════════════════════════════════════════════════════════════════
-- Close button
-- ═══════════════════════════════════════════════════════════════════════════
UITheme.CLOSE_DEFAULT = Color3.fromRGB(26, 30, 48)
UITheme.CLOSE_HOVER   = Color3.fromRGB(55, 30, 38)
UITheme.CLOSE_PRESS   = Color3.fromRGB(18, 20, 32)

-- ═══════════════════════════════════════════════════════════════════════════
-- Options / sliders / toggles
-- ═══════════════════════════════════════════════════════════════════════════
UITheme.TOGGLE_ON     = Color3.fromRGB(35, 190, 75)
UITheme.TOGGLE_OFF    = Color3.fromRGB(45, 48, 65)
UITheme.SLIDER_TRACK  = Color3.fromRGB(35, 38, 55)
UITheme.KNOB_COLOR    = Color3.fromRGB(255, 255, 255)

-- ═══════════════════════════════════════════════════════════════════════════
-- Progress bars
-- ═══════════════════════════════════════════════════════════════════════════
UITheme.BAR_BG       = Color3.fromRGB(35, 38, 58)
UITheme.BAR_FILL     = UITheme.GOLD

-- ═══════════════════════════════════════════════════════════════════════════
-- Popup / overlay
-- ═══════════════════════════════════════════════════════════════════════════
UITheme.POPUP_BG     = Color3.fromRGB(16, 18, 32)
UITheme.OVERLAY_CLR  = Color3.fromRGB(10, 10, 10)

-- ═══════════════════════════════════════════════════════════════════════════
-- Upgrade pips
-- ═══════════════════════════════════════════════════════════════════════════
UITheme.PIP_ACTIVE   = UITheme.GOLD
UITheme.PIP_INACTIVE = Color3.fromRGB(50, 54, 72)

-- ═══════════════════════════════════════════════════════════════════════════
-- Panel gradient (subtle vertical gradient matching Team menu)
-- ═══════════════════════════════════════════════════════════════════════════
UITheme.PANEL_GRADIENT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(185, 185, 195)),
})
UITheme.PANEL_GRADIENT_ROTATION = 90

-- ═══════════════════════════════════════════════════════════════════════════
-- Row card gradient (subtle depth for settings rows)
-- ═══════════════════════════════════════════════════════════════════════════
UITheme.ROW_GRADIENT = ColorSequence.new(
	Color3.fromRGB(30, 35, 55),
	Color3.fromRGB(22, 26, 42)
)

-- ═══════════════════════════════════════════════════════════════════════════
-- Numeric display helpers  (round floating-point stat values for UI display)
-- ═══════════════════════════════════════════════════════════════════════════

--- Round a numeric value to the nearest whole number for player-facing display.
--- Non-numeric inputs pass through as-is via tostring.
function UITheme.FormatInt(value)
	local n = tonumber(value)
	if not n then return tostring(value) end
	return tostring(math.floor(n + 0.5))
end

--- Format a progress / goal pair as "current / goal" with rounded integers.
function UITheme.FormatProgress(current, goal)
	return UITheme.FormatInt(current) .. "/" .. UITheme.FormatInt(goal)
end

return UITheme
