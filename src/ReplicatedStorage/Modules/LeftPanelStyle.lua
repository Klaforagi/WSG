--------------------------------------------------------------------------------
-- LeftPanelStyle.lua  –  Shared left-side tab-panel sizing/style constants.
--
-- Used by ShopUI, InventoryUI, and DailyQuestsUI so all three left panels
-- feel identical (button size, padding, corner radius, stroke, icon spacing,
-- selected/unselected colors, hover behavior).
--
-- Each consumer still constructs its own buttons; this module only supplies
-- the numbers/colors. That keeps the individual structures intact while
-- normalizing the visual rules.
--------------------------------------------------------------------------------

local UITheme = require(script.Parent.Parent.SideUI.UITheme)

local LeftPanelStyle = {}

-- Sizing (in 1080p reference pixels — call px(value) when using these).
LeftPanelStyle.TAB_W           = 132   -- sidebar width
LeftPanelStyle.TAB_H           = 62    -- tab button height
LeftPanelStyle.TAB_GAP         = 10    -- gap between sidebar and content
LeftPanelStyle.TAB_LIST_PAD    = 3     -- spacing between buttons
LeftPanelStyle.SIDE_PAD_X      = 6     -- inner left/right padding
LeftPanelStyle.SIDE_PAD_Y      = 10    -- inner top/bottom padding
LeftPanelStyle.BTN_INSET       = 2     -- horizontal inset for each button
LeftPanelStyle.CORNER_RADIUS   = 10    -- UICorner radius
LeftPanelStyle.STROKE_THICK    = 1.2   -- UIStroke thickness
LeftPanelStyle.STROKE_TRANSP   = 0.6   -- UIStroke transparency
LeftPanelStyle.ACTIVE_BAR_W    = 3     -- left active indicator width
LeftPanelStyle.ICON_HEIGHT     = 24    -- icon row height
LeftPanelStyle.ICON_TOP_OFFSET = 8     -- icon Y offset
LeftPanelStyle.ICON_TEXT_SIZE  = 20    -- glyph icon font size
LeftPanelStyle.LABEL_HEIGHT    = 16
LeftPanelStyle.LABEL_TOP_OFFSET= 34    -- label Y offset
LeftPanelStyle.LABEL_TEXT_SIZE = 13    -- label font size
LeftPanelStyle.LABEL_X_INSET   = 3     -- label horizontal inset

-- Tween durations (for hover animation).
LeftPanelStyle.HOVER_TWEEN_TIME = 0.12

-- Fonts.
LeftPanelStyle.LABEL_FONT = Enum.Font.GothamBold
LeftPanelStyle.ICON_FONT  = Enum.Font.GothamBold

-- Colors (sourced from UITheme so they stay in lockstep).
LeftPanelStyle.SIDEBAR_BG       = UITheme.SIDEBAR_BG
LeftPanelStyle.BTN_BG_INACTIVE  = UITheme.SIDEBAR_BG
LeftPanelStyle.BTN_BG_HOVER     = Color3.fromRGB(28, 26, 18)
LeftPanelStyle.BTN_BG_ACTIVE    = Color3.fromRGB(34, 32, 22)
LeftPanelStyle.STROKE_COLOR     = UITheme.CARD_STROKE
LeftPanelStyle.LABEL_INACTIVE   = UITheme.DIM_TEXT
LeftPanelStyle.LABEL_ACTIVE     = UITheme.GOLD
LeftPanelStyle.ICON_INACTIVE    = UITheme.DIM_TEXT
LeftPanelStyle.ICON_ACTIVE      = UITheme.GOLD
LeftPanelStyle.ACTIVE_BAR_COLOR = UITheme.GOLD

return LeftPanelStyle
