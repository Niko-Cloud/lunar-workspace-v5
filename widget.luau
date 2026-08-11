-- Lunar Workspaces bar widget
-- Renders one pill per workspace (focused/urgent/occupied/empty), reading
-- state from the background service (service.luau) via noctalia.state.watch().

local STATE_KEY = "lunar_workspaces"

local wsState = noctalia.state.get(STATE_KEY) or {}
local renderedVertical = nil

local compositorSetting = noctalia.getConfig("compositor") or "auto"
local displayMode = noctalia.getConfig("workspace_display_mode") or "all"
local workspaceCount = tonumber(noctalia.getConfig("workspace_count")) or 9

local iconFocused = noctalia.getConfig("icon_focused") or "🌕"
local iconUrgent = noctalia.getConfig("icon_urgent") or "🌟"
local iconOccupied = noctalia.getConfig("icon_occupied") or "🌗"
local iconEmpty = noctalia.getConfig("icon_empty") or "🌙"

local sizeFocused = tonumber(noctalia.getConfig("size_focused")) or 22
local sizeUrgent = tonumber(noctalia.getConfig("size_urgent")) or 20
local sizeOccupied = tonumber(noctalia.getConfig("size_occupied")) or 18
local sizeEmpty = tonumber(noctalia.getConfig("size_empty")) or 16

local focusedPillStyle = noctalia.getConfig("focused_pill_style") or "fill"
local focusedColor = noctalia.getConfig("focused_color") or "primary"
local urgentPillStyle = noctalia.getConfig("urgent_pill_style") or "fill"
local urgentColor = noctalia.getConfig("urgent_color") or "error"
local occupiedPillStyle = noctalia.getConfig("occupied_pill_style") or "ghost"
local occupiedColor = noctalia.getConfig("occupied_color") or "secondary"
local emptyPillStyle = noctalia.getConfig("empty_pill_style") or "ghost"
local emptyColor = noctalia.getConfig("empty_color") or "surface_variant"

-- True if an icon setting value looks like an image path rather than an
-- emoji or plain glyph. Strips a "file://" prefix (added by the native file
-- picker) before checking.
local function isImagePath(v)
	if type(v) ~= "string" then
		return false
	end
	local path = v:gsub("^file://", "")
	if path:sub(1, 1) == "/" then
		return true
	end
	return path:lower():match("%.%a+$") ~= nil
		and (path:lower():match("%.png$") or path:lower():match("%.jpe?g$")
			or path:lower():match("%.gif$") or path:lower():match("%.webp$")
			or path:lower():match("%.svg$")) ~= nil
end

-- Normalizes an icon setting value into a plain filesystem path.
local function imagePathFor(v)
	return (v:gsub("^file://", ""))
end

local function entryFor(idxStr)
	return wsState[idxStr] or { focused = false, urgent = false, occupied = false }
end

local function iconFor(entry)
	if entry.focused then
		return iconFocused
	elseif entry.urgent then
		return iconUrgent
	elseif entry.occupied then
		return iconOccupied
	end
	return iconEmpty
end

local function sizeFor(entry)
	if entry.focused then
		return sizeFocused
	elseif entry.urgent then
		return sizeUrgent
	elseif entry.occupied then
		return sizeOccupied
	end
	return sizeEmpty
end

-- Workspace indices to render, per workspace_display_mode:
--   all             - every workspace from 1..workspace_count
--   active_occupied - only occupied, focused, or urgent workspaces
--   once            - occupied/focused/urgent workspaces, plus a single
--                     "anticipatory" empty slot right after the last
--                     occupied one, so there's always one place to go next
local function visibleIndices()
	local indices = {}

	if displayMode == "active_occupied" then
		for i = 1, workspaceCount do
			local e = entryFor(tostring(i))
			if e.occupied or e.focused or e.urgent then
				table.insert(indices, i)
			end
		end
	elseif displayMode == "once" then
		local maxOccupied = 0
		for i = 1, workspaceCount do
			local e = entryFor(tostring(i))
			if e.occupied then
				maxOccupied = i
			end
		end

		local shown = {}
		for i = 1, workspaceCount do
			local e = entryFor(tostring(i))
			if e.occupied or e.focused or e.urgent then
				table.insert(indices, i)
				shown[i] = true
			end
		end

		local anticipatory
		for i = maxOccupied + 1, workspaceCount do
			local e = entryFor(tostring(i))
			if not e.occupied then
				anticipatory = i
				break
			end
		end
		if anticipatory and not shown[anticipatory] then
			table.insert(indices, anticipatory)
		end
	else -- "all"
		for i = 1, workspaceCount do
			table.insert(indices, i)
		end
	end

	table.sort(indices)

	if #indices == 0 then
		table.insert(indices, 1)
	end

	return indices
end

-- Switches to the given workspace index on whichever compositor is active.
local function switchWorkspace(idx)
	local useHyprland
	if compositorSetting == "hyprland" then
		useHyprland = true
	elseif compositorSetting == "niri" then
		useHyprland = false
	else
		useHyprland = noctalia.commandExists("hyprctl") and noctalia.getenv("HYPRLAND_INSTANCE_SIGNATURE") ~= nil
	end

	if useHyprland then
		noctalia.runAsync("hyprctl dispatch workspace " .. idx)
	else
		noctalia.runAsync("niri msg action focus-workspace " .. idx)
	end
end

-- Builds and renders the row/column of workspace pills.
local function render(vertical)
	renderedVertical = vertical
	local container = vertical and ui.column or ui.row
	local pill = vertical and ui.column or ui.row
	local children = {}

	for _, idx in ipairs(visibleIndices()) do
		local idxStr = tostring(idx)
		local entry = entryFor(idxStr)
		local glyphOrPath = iconFor(entry)
		local size = sizeFor(entry)

		-- "ghost" = transparent, bare icon. "fill" = colored pill behind it.
		local style, color
		if entry.focused then
			style, color = focusedPillStyle, focusedColor
		elseif entry.urgent then
			style, color = urgentPillStyle, urgentColor
		elseif entry.occupied then
			style, color = occupiedPillStyle, occupiedColor
		else
			style, color = emptyPillStyle, emptyColor
		end

		local fill = "#00000000"
		local textColor = "on_surface"
		if style == "fill" then
			fill = color
			textColor = "on_" .. color
		end

		local inner
		if isImagePath(glyphOrPath) then
			-- `key` keeps this node's identity stable across re-renders so
			-- image playback isn't restarted on every state update.
			inner = ui.image({
				key = "icon-" .. idxStr,
				path = imagePathFor(glyphOrPath),
				width = size,
				height = size,
			})
		else
			inner = ui.label({ text = glyphOrPath, fontSize = size, color = textColor, textAlign = "center" })
		end

		table.insert(
			children,
			pill({
				key = idxStr,
				align = "center",
				justify = "center",
				fill = fill,
				radius = 8,
				onClick = function()
					switchWorkspace(idxStr)
				end,
			}, { inner })
		)
	end

	barWidget.render(container({ gap = 6, align = "center" }, children))
end

noctalia.state.watch(STATE_KEY, function(value)
	wsState = type(value) == "table" and value or {}
	render(renderedVertical)
end)

function update()
	local vertical = barWidget.isVertical()
	if vertical ~= renderedVertical then
		render(vertical)
	end
end

function onConfigChanged()
	compositorSetting = noctalia.getConfig("compositor") or "auto"
	displayMode = noctalia.getConfig("workspace_display_mode") or "all"
	workspaceCount = tonumber(noctalia.getConfig("workspace_count")) or 9
	iconFocused = noctalia.getConfig("icon_focused") or "🌕"
	iconUrgent = noctalia.getConfig("icon_urgent") or "🌟"
	iconOccupied = noctalia.getConfig("icon_occupied") or "🌗"
	iconEmpty = noctalia.getConfig("icon_empty") or "🌙"
	sizeFocused = tonumber(noctalia.getConfig("size_focused")) or 22
	sizeUrgent = tonumber(noctalia.getConfig("size_urgent")) or 20
	sizeOccupied = tonumber(noctalia.getConfig("size_occupied")) or 18
	sizeEmpty = tonumber(noctalia.getConfig("size_empty")) or 16
	focusedPillStyle = noctalia.getConfig("focused_pill_style") or "fill"
	focusedColor = noctalia.getConfig("focused_color") or "primary"
	urgentPillStyle = noctalia.getConfig("urgent_pill_style") or "fill"
	urgentColor = noctalia.getConfig("urgent_color") or "error"
	occupiedPillStyle = noctalia.getConfig("occupied_pill_style") or "ghost"
	occupiedColor = noctalia.getConfig("occupied_color") or "secondary"
	emptyPillStyle = noctalia.getConfig("empty_pill_style") or "ghost"
	emptyColor = noctalia.getConfig("empty_color") or "surface_variant"
	render(renderedVertical)
end

-- Scroll-to-switch: moves focus to the next/previous visible workspace.
function onScroll(axis, steps, startsGesture)
	if not startsGesture then
		return
	end
	local visible = visibleIndices()
	local currentPos = nil
	for pos, idx in ipairs(visible) do
		if entryFor(tostring(idx)).focused then
			currentPos = pos
			break
		end
	end
	if currentPos == nil then
		return
	end
	local delta = (steps > 0) and 1 or -1
	local nextPos = ((currentPos - 1 + delta) % #visible) + 1
	switchWorkspace(tostring(visible[nextPos]))
end

render(barWidget.isVertical())
