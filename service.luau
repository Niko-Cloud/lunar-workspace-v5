-- Lunar Workspaces — background service
-- Watches Hyprland or Niri and publishes per-workspace state so the bar
-- widget can render it:
--   { ["1"] = { focused = true, urgent = false, occupied = true }, ... }

local STATE_KEY = "lunar_workspaces"

local compositorSetting = noctalia.getConfig("compositor") or "auto"
local detectedCompositor = nil -- "hyprland" | "niri" | nil

local loggedError = false
local function logOnce(msg)
	if not loggedError then
		noctalia.log("Lunar Workspaces: " .. msg)
		loggedError = true
	end
end

-- Resolves the "compositor" setting to an actual compositor, auto-detecting
-- via env vars and available binaries when set to "auto".
local function detectCompositor()
	if compositorSetting == "hyprland" or compositorSetting == "niri" then
		return compositorSetting
	end
	if noctalia.getenv("HYPRLAND_INSTANCE_SIGNATURE") and noctalia.commandExists("hyprctl") then
		return "hyprland"
	end
	if noctalia.getenv("NIRI_SOCKET") and noctalia.commandExists("niri") then
		return "niri"
	end
	if noctalia.commandExists("hyprctl") then
		return "hyprland"
	end
	if noctalia.commandExists("niri") then
		return "niri"
	end
	return nil
end

-- Hyprland

local SEPARATOR = "__LUNAR_WORKSPACES_SEP__"

local hyprRefreshInFlight = false
local hyprRefreshPending = false

-- Parses hyprctl JSON output and publishes normalized workspace state.
local function publishHyprland(workspacesJson, activeJson, clientsJson)
	local workspaces = noctalia.json.decode(workspacesJson)
	local active = noctalia.json.decode(activeJson)
	local clients = noctalia.json.decode(clientsJson)
	if type(workspaces) ~= "table" then
		logOnce("invalid hyprctl workspaces JSON")
		return
	end

	local activeId = active and active.id
	local urgentWs = {}
	if type(clients) == "table" then
		for _, c in ipairs(clients) do
			if c.urgent and c.workspace and c.workspace.id then
				urgentWs[c.workspace.id] = true
			end
		end
	end

	local out = {}
	for _, ws in ipairs(workspaces) do
		out[tostring(ws.id)] = {
			focused = (ws.id == activeId),
			urgent = urgentWs[ws.id] == true,
			occupied = (ws.windows or 0) > 0,
		}
	end
	loggedError = false
	noctalia.state.set(STATE_KEY, out)
end

-- Snapshots hyprctl workspaces/activeworkspace/clients in one shell round
-- trip and republishes state. Coalesces overlapping calls into one retry.
local function refreshHyprland()
	if hyprRefreshInFlight then
		hyprRefreshPending = true
		return
	end
	hyprRefreshInFlight = true

	local command = "printf '%s\\n"
		.. SEPARATOR
		.. "\\n%s\\n"
		.. SEPARATOR
		.. "\\n%s\\n' \"$(hyprctl -j workspaces)\" \"$(hyprctl -j activeworkspace)\" \"$(hyprctl -j clients)\""

	local started = noctalia.runAsync(command, function(result)
		hyprRefreshInFlight = false
		if result.exitCode == 0 then
			local first, firstEnd = string.find(result.stdout, "\n" .. SEPARATOR .. "\n", 1, true)
			local second, secondEnd = string.find(result.stdout, "\n" .. SEPARATOR .. "\n", firstEnd and (firstEnd + 1) or 1, true)
			if first and second then
				local wsJson = string.sub(result.stdout, 1, first - 1)
				local activeJson = string.sub(result.stdout, firstEnd + 1, second - 1)
				local clientsJson = string.sub(result.stdout, secondEnd + 1)
				publishHyprland(wsJson, activeJson, clientsJson)
			else
				logOnce("incomplete hyprctl snapshot")
			end
		else
			logOnce("hyprctl failed")
		end
		if hyprRefreshPending then
			hyprRefreshPending = false
			refreshHyprland()
		end
	end)

	if not started then
		hyprRefreshInFlight = false
		logOnce("could not start hyprctl snapshot")
	end
end

-- Hyprland IPC events that should trigger a state refresh.
local hyprEvents = {
	workspace = true,
	workspacev2 = true,
	createworkspace = true,
	createworkspacev2 = true,
	destroyworkspace = true,
	destroyworkspacev2 = true,
	moveworkspace = true,
	moveworkspacev2 = true,
	openwindow = true,
	closewindow = true,
	movewindow = true,
	movewindowv2 = true,
	urgent = true,
	focusedmon = true,
	focusedmonv2 = true,
}

-- Tails the Hyprland IPC socket via socat for instant updates. Falls back to
-- poll-only mode (the 60s resync tick) if socat or the socket isn't available.
local function startHyprlandEventStream()
	if not noctalia.commandExists("socat") then
		logOnce("socat unavailable; falling back to poll-only Hyprland updates")
		return
	end
	local runtimeDir = noctalia.getenv("XDG_RUNTIME_DIR")
	local signature = noctalia.getenv("HYPRLAND_INSTANCE_SIGNATURE")
	if not runtimeDir or not signature then
		logOnce("Hyprland environment unavailable; poll-only mode")
		return
	end

	local socket = runtimeDir .. "/hypr/" .. signature .. "/.socket2.sock"
	local command = "while true; do while [ ! -S '"
		.. socket
		.. "' ]; do sleep 5; done; socat -u UNIX-CONNECT:'"
		.. socket
		.. "' - 2>&1; sleep 5; done"

	noctalia.runStream(command, function(line)
		local event = string.match(line, "^([%a%d_]+)>>")
		if event and hyprEvents[event] then
			refreshHyprland()
		end
	end)
end

-- Niri

-- Publishes normalized state from a Niri workspace list.
local function publishNiri(list)
	local out = {}
	for _, ws in ipairs(list) do
		local idx = ws.idx or ws.id
		out[tostring(idx)] = {
			focused = ws.is_focused == true,
			urgent = ws.is_urgent == true,
			occupied = ws.active_window_id ~= nil,
		}
	end
	loggedError = false
	noctalia.state.set(STATE_KEY, out)
end

-- Fetches the current workspace list from niri and republishes state.
local function refreshNiri()
	noctalia.runAsync("niri msg --json workspaces", function(result)
		if result.exitCode ~= 0 then
			logOnce("niri msg failed")
			return
		end
		local data = noctalia.json.decode(result.stdout)
		if type(data) == "table" then
			publishNiri(data)
		end
	end, 3000)
end

-- Tails niri's JSON event stream and re-snapshots on any workspace change.
local function startNiriEventStream()
	noctalia.runStream("niri msg --json event-stream", function(line)
		local ev = noctalia.json.decode(line)
		if type(ev) ~= "table" then
			return
		end
		if ev.WorkspacesChanged ~= nil then
			publishNiri(ev.WorkspacesChanged.workspaces or {})
		elseif ev.WorkspaceActivated ~= nil then
			refreshNiri()
		end
	end)
end

-- Wiring

local function start()
	detectedCompositor = detectCompositor()
	if detectedCompositor == "hyprland" then
		refreshHyprland()
		startHyprlandEventStream()
	elseif detectedCompositor == "niri" then
		refreshNiri()
		startNiriEventStream()
	else
		logOnce("no supported compositor detected (hyprctl/niri not found)")
	end
end

start()

-- Periodic resync as a safety net alongside the live event streams.
noctalia.setUpdateInterval(60000)

function update()
	if detectedCompositor == "hyprland" then
		refreshHyprland()
	elseif detectedCompositor == "niri" then
		refreshNiri()
	else
		start() -- retry detection in case the compositor started after us
	end
end

function onConfigChanged()
	compositorSetting = noctalia.getConfig("compositor") or "auto"
	start()
end

function onOutputsChanged()
	if detectedCompositor == "hyprland" then
		refreshHyprland()
	elseif detectedCompositor == "niri" then
		refreshNiri()
	end
end
