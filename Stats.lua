-- Polypode Histoire: Stats — relevés des statistiques des personnages et vue « Stats » (1.24.0)
--
-- Le jeu ne donne que la valeur actuelle d'une statistique (onglet Statistiques du panneau du
-- personnage sur WoW Forever : GetStatisticsCategoryList, GetCategoryInfo, GetStatistic) ; aucun
-- historique. On relève donc soi-même les valeurs, au plus un point par jour et par statistique, et
-- seulement quand la valeur change (à la connexion, STATS_DELAY s après un CRITERIA_UPDATE, à la
-- déconnexion), pour tracer leur évolution dans l'infobulle de la vue « Stats ».
--
-- Stockage : série = suite de points (jour AAAAMMJJ, valeur), écrite « jour:valeur;jour:valeur »
-- dans les fichiers, gardée en tables pendant la session (dépliée au chargement, repliée à
-- PLAYER_LOGOUT). Chaque personnage garde ses relevés dans PolypodeHistoireChar.stats (fichier écrit
-- par son seul client : la référence), recopiés avec ceux des autres dans
-- PolypodeHistoireData.stats[clé] (le fichier commun, lu par tous les personnages). À la connexion,
-- les deux sont fusionnés (union des points). Pendant la session, chaque nouveau point est envoyé
-- aux autres clients (HIST:token:S:clé~jour~id=valeur,id=valeur...), et les points de la session
-- sont renvoyés à un client qui s'annonce : le dernier client qui quitte écrit le fichier commun à
-- jour.
--
-- WoW Forever d'abord : sur Retail, certaines valeurs sont mises en forme (or, durées) ; ni relevés
-- ni bouton « Stats » tant que STATS_ENABLED est faux.

local _, ns = ...
local P = Polypode
local L = ns.L
local H = ns.H

local STATS_ENABLED = not H.IS_RETAIL
local STATS_DELAY = 30 -- secondes : regroupe les CRITERIA_UPDATE (très fréquents)
local LOGIN_DELAY = 5 -- secondes : statistiques chargées après l'entrée dans le monde
local CHUNK = 200 -- longueur maximale de la liste « id=valeur » d'un message
local DAY = 86400

ns.STATS_ENABLED = STATS_ENABLED

local data = {} -- [clé] = { class, since = jour du premier relevé, s = { [id] = { d = { jours }, v = { valeurs } } } }
local myKey
local sessionChanged = {} -- [id] = true : statistiques du personnage joué changées pendant la session
local categories -- arbre des catégories (Categories), construit une fois
local pending -- relevé programmé (CRITERIA_UPDATE)

-- OUTILS ------------------------------------------------------------------------------------------

local function Today()
	return tonumber(date("%Y%m%d"))
end

-- Heure de début (0 h) d'un jour AAAAMMJJ.
local function DayTime(day)
	return time({ year = math.floor(day / 10000), month = math.floor(day / 100) % 100, day = day % 100, hour = 0 })
end

local function AddDays(day, n)
	return tonumber(date("%Y%m%d", DayTime(day) + 12 * 3600 + n * DAY))
end

local function Number(value)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value)
end

-- Valeur affichée par le jeu → nombre (« -- » = 0) ; nil si illisible (texte mis en forme, secret).
local function ParseValue(quantity)
	if quantity == nil or (issecretvalue and issecretvalue(quantity)) then
		return nil
	end
	if quantity == "--" then
		return 0
	end
	return tonumber(quantity)
end

-- SÉRIES ------------------------------------------------------------------------------------------

local function NewSeries()
	return { d = {}, v = {} }
end

-- Pose la valeur d'un jour (remplace celle du même jour), à sa place dans l'ordre des jours.
local function Insert(series, day, value)
	local d, v = series.d, series.v
	local i = #d
	while i > 0 and d[i] > day do
		i = i - 1
	end
	if i > 0 and d[i] == day then
		v[i] = value
	else
		table.insert(d, i + 1, day)
		table.insert(v, i + 1, value)
	end
end

local function Unpack(text)
	local series = NewSeries()
	if type(text) == "string" then
		for day, value in text:gmatch("(%d+):(%d+)") do
			Insert(series, tonumber(day), tonumber(value))
		end
	end
	return series
end

local function Pack(series)
	local parts = {}
	for i = 1, #series.d do
		parts[i] = series.d[i] .. ":" .. series.v[i]
	end
	return table.concat(parts, ";")
end

local function UnpackChar(saved)
	local entry = { s = {} }
	if type(saved) == "table" then
		entry.class, entry.since = saved.class, tonumber(saved.since)
		for id, text in pairs(type(saved.s) == "table" and saved.s or {}) do
			if tonumber(id) then
				entry.s[tonumber(id)] = Unpack(text)
			end
		end
	end
	return entry
end

local function PackChar(entry)
	local saved = { class = entry.class, since = entry.since, s = {} }
	for id, series in pairs(entry.s) do
		if #series.d > 0 then
			saved.s[id] = Pack(series)
		end
	end
	return saved
end

-- Union des points de source dans dest (même jour : valeur de source).
local function Merge(dest, source)
	dest.class = dest.class or source.class
	if source.since and (not dest.since or source.since < dest.since) then
		dest.since = source.since
	end
	for id, series in pairs(source.s) do
		local target = dest.s[id]
		if not target then
			target = NewSeries()
			dest.s[id] = target
		end
		for i = 1, #series.d do
			Insert(target, series.d[i], series.v[i])
		end
	end
end

-- Valeur d'une série au soir d'un jour donné. Avant le premier point : la valeur au premier relevé du
-- personnage (since) si la série commence ce jour-là, sinon 0 (statistique encore nulle).
local function ValueAt(series, day, since)
	local d = series.d
	for i = #d, 1, -1 do
		if d[i] <= day then
			return series.v[i]
		end
	end
	return (since and d[1] and d[1] <= since) and series.v[1] or 0
end

local function Last(series)
	return series.v[#series.v] or 0
end

-- CATÉGORIES --------------------------------------------------------------------------------------

-- Arbre des catégories de statistiques, dans l'ordre du jeu : { ordered = { nœuds }, roots = { nœuds } },
-- nœud = { id, name, parent, depth, children, stats = { ids } }. nil si le client n'a pas l'API.
local function Categories()
	if categories then
		return categories
	end
	local list = GetStatisticsCategoryList and GetStatisticsCategoryList()
	if type(list) ~= "table" or not GetCategoryInfo or not GetCategoryNumAchievements or not GetStatistic then
		return nil
	end
	local byID, nodes = {}, {}
	for _, id in ipairs(list) do
		local name, parent = GetCategoryInfo(id)
		local node = { id = id, name = name or "?", parent = parent, children = {}, stats = {} }
		for i = 1, GetCategoryNumAchievements(id) or 0 do
			local _, skip, statID = GetStatistic(id, i)
			if statID and not skip then
				node.stats[#node.stats + 1] = statID
			end
		end
		byID[id] = node
		nodes[#nodes + 1] = node
	end
	local roots = {}
	for _, node in ipairs(nodes) do
		local parent = node.parent and byID[node.parent]
		if parent then
			parent.children[#parent.children + 1] = node
		else
			roots[#roots + 1] = node
		end
	end
	local ordered = {}
	local function Walk(node, depth)
		node.depth = depth
		ordered[#ordered + 1] = node
		for _, child in ipairs(node.children) do
			Walk(child, depth + 1)
		end
	end
	for _, node in ipairs(roots) do
		Walk(node, 1)
	end
	categories = { ordered = ordered, roots = roots }
	return categories
end

-- SYNCHRO -----------------------------------------------------------------------------------------

-- Envoie le dernier point des statistiques ids du personnage joué (groupés par jour, découpés).
local function SendLast(ids, target)
	local mine = myKey and data[myKey]
	if not mine or not ns.Send then
		return
	end
	local byDay = {}
	for _, id in ipairs(ids) do
		local series = mine.s[id]
		local n = series and #series.d or 0
		if n > 0 then
			local day = series.d[n]
			byDay[day] = byDay[day] or {}
			table.insert(byDay[day], id .. "=" .. series.v[n])
		end
	end
	for day, parts in pairs(byDay) do
		local chunk = {}
		local length = 0
		for i, part in ipairs(parts) do
			chunk[#chunk + 1] = part
			length = length + #part + 1
			if length >= CHUNK or i == #parts then
				ns.Send("S", myKey .. "~" .. day .. "~" .. table.concat(chunk, ","), target)
				chunk, length = {}, 0
			end
		end
	end
end

-- Points reçus d'un autre personnage (seulement de lui-même).
function ns.OnStatsMessage(payload, sender)
	if not STATS_ENABLED then
		return
	end
	local key, day, list = strsplit("~", payload, 3)
	day = tonumber(day)
	if not (key and day and list) or key == myKey or not (ns.FromItsCharacter and ns.FromItsCharacter(sender, key)) then
		return
	end
	local entry = data[key]
	if not entry then
		entry = { s = {} }
		data[key] = entry
	end
	entry.since = entry.since or day
	for id, value in list:gmatch("(%d+)=(%d+)") do
		id = tonumber(id)
		entry.s[id] = entry.s[id] or NewSeries()
		Insert(entry.s[id], day, tonumber(value))
	end
	if ns.RefreshStats then
		ns.RefreshStats()
	end
end

-- Un client s'annonce : il reçoit les points de notre session (absents du fichier qu'il a lu).
function ns.OnStatsPeer(sender)
	local ids = {}
	for id in pairs(sessionChanged) do
		ids[#ids + 1] = id
	end
	if #ids > 0 then
		SendLast(ids, sender)
	end
end

-- RELEVÉS -----------------------------------------------------------------------------------------

-- Relève les statistiques du personnage joué : un point pour chaque valeur non nulle qui a changé.
local function Snapshot()
	pending = nil
	local cats = myKey and Categories()
	if not cats then
		return
	end
	local mine = data[myKey]
	local today = Today()
	mine.since = mine.since or today
	local changed = {}
	for _, node in ipairs(cats.ordered) do
		for _, id in ipairs(node.stats) do
			local value = ParseValue(GetStatistic(id))
			if value and value > 0 then
				local series = mine.s[id]
				if not series then
					series = NewSeries()
					mine.s[id] = series
				end
				local n = #series.v
				if n == 0 or series.v[n] ~= value then
					Insert(series, today, value)
					changed[#changed + 1] = id
					sessionChanged[id] = true
				end
			end
		end
	end
	if #changed > 0 then
		SendLast(changed)
		if ns.RefreshStats then
			ns.RefreshStats()
		end
	end
end
ns.SnapshotStats = Snapshot

local function OnLogin()
	myKey = ns.CharKey()
	local entry = data[myKey] or { s = {} }
	PolypodeHistoireChar = PolypodeHistoireChar or {}
	Merge(entry, UnpackChar(PolypodeHistoireChar.stats))
	entry.class = select(2, UnitClass("player")) or entry.class
	data[myKey] = entry
	C_Timer.After(LOGIN_DELAY, Snapshot)
end

local function Save()
	local all = {}
	for key, entry in pairs(data) do
		if next(entry.s) then
			all[key] = PackChar(entry)
		end
	end
	PolypodeHistoireData.stats = all
	if myKey and data[myKey] then
		PolypodeHistoireChar = PolypodeHistoireChar or {}
		PolypodeHistoireChar.stats = PackChar(data[myKey])
	end
end

if STATS_ENABLED then
	local events = CreateFrame("Frame")
	events:RegisterEvent("ADDON_LOADED")
	events:RegisterEvent("PLAYER_LOGIN")
	events:RegisterEvent("PLAYER_LOGOUT")
	events:RegisterEvent("CRITERIA_UPDATE")
	events:SetScript("OnEvent", function(_, event, arg)
		if event == "ADDON_LOADED" then
			if arg == "Polypode_Histoire" then
				PolypodeHistoireData = PolypodeHistoireData or {}
				for key, saved in pairs(type(PolypodeHistoireData.stats) == "table" and PolypodeHistoireData.stats or {}) do
					data[key] = UnpackChar(saved)
				end
			end
		elseif event == "PLAYER_LOGIN" then
			OnLogin()
		elseif event == "PLAYER_LOGOUT" then
			if myKey then
				Snapshot()
				Save()
			end
		elseif event == "CRITERIA_UPDATE" then
			if myKey and not pending then
				pending = true
				C_Timer.After(STATS_DELAY, Snapshot)
			end
		end
	end)
end

-- VUE « STATS » -----------------------------------------------------------------------------------

local ROW_H = { [1] = 26, [2] = 22 }
local STAT_H = 18
local COL_W = 64
local NAME_MIN = 180 -- largeur minimale du nom : sinon une seule colonne « Tous »
local INDENT = 14
local GOLD = { 1, 0.82, 0.2 }
local DELTA_DAYS = 7

local panel, list, searchBox, columnHeader, countText
local columns = {} -- colonnes affichées : { key, label } (personnages, ou « Tous »), puis « 7 j »

local function Settings()
	local settings = H.Settings()
	settings.statsClosed = settings.statsClosed or {}
	return settings
end

local function ClassColor(key)
	local entry = ns.RosterEntry and ns.RosterEntry(key)
	local class = entry and entry.class or (data[key] and data[key].class)
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if color then
		return color.r, color.g, color.b
	end
	return 0.8, 0.8, 0.8
end

-- Nom court (prénom) à la couleur de la classe.
local function ShortName(key)
	local entry = ns.RosterEntry and ns.RosterEntry(key)
	local name = entry and entry.name or key:match("^[^%s%-]+") or key
	local r, g, b = ClassColor(key)
	return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, name)
end

-- Personnages ayant des relevés, triés par nom.
local function Characters()
	local keys = {}
	for key, entry in pairs(data) do
		if next(entry.s) then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys, function(a, b)
		return (ns.Identity and ns.Identity(a) or a) < (ns.Identity and ns.Identity(b) or b)
	end)
	return keys
end

local function StatName(id)
	return GetAchievementInfo and select(2, GetAchievementInfo(id)) or ("n° " .. id)
end

-- Écart sur DELTA_DAYS jours, tous personnages : valeur actuelle − valeur au soir du jour d'avant.
local function Delta(id, keys, days)
	local from = AddDays(Today(), -days)
	local total = 0
	for _, key in ipairs(keys) do
		local series = data[key].s[id]
		if series and #series.d > 0 then
			total = total + Last(series) - ValueAt(series, from, data[key].since)
		end
	end
	return total
end

-- Lignes de la liste : catégories (titres repliables) puis statistiques ayant une valeur pour au
-- moins un personnage ; recherche : statistiques dont le nom contient le texte, tout déplié.
local function BuildItems(keys)
	local cats = Categories()
	if not cats then
		return {}
	end
	local search = searchBox and searchBox:GetText():lower() or ""
	local closed = Settings().statsClosed
	local items = {}
	local function Add(node)
		local rows = {}
		for _, id in ipairs(node.stats) do
			local values, any = {}, false
			for _, key in ipairs(keys) do
				local series = data[key].s[id]
				local value = series and Last(series) or 0
				values[key] = value
				any = any or value > 0
			end
			local name = StatName(id)
			if any and (search == "" or name:lower():find(search, 1, true)) then
				rows[#rows + 1] = { stat = id, name = name, values = values, delta = Delta(id, keys, DELTA_DAYS),
					category = node.name, depth = node.depth }
			end
		end
		local childItems = {}
		for _, child in ipairs(node.children) do
			for _, item in ipairs(Add(child)) do
				childItems[#childItems + 1] = item
			end
		end
		if #rows == 0 and #childItems == 0 then
			return {}
		end
		local result = { { header = node.depth == 1 and 1 or 2, id = node.id, name = node.name, depth = node.depth,
			count = #rows } }
		if search ~= "" or not closed[node.id] then
			for _, row in ipairs(rows) do
				result[#result + 1] = row
			end
			for _, item in ipairs(childItems) do
				result[#result + 1] = item
			end
		end
		return result
	end
	for _, node in ipairs(cats.roots) do
		for _, item in ipairs(Add(node)) do
			items[#items + 1] = item
		end
	end
	return items
end

-- INFOBULLE À GRAPHIQUE ---------------------------------------------------------------------------

local CHART_W, CHART_H, AXIS_W, TIP_W = 250, 110, 52, 330
local tip

local function BuildTip()
	tip = CreateFrame("Frame", "PolypodeHistoireStatsTip", UIParent, "BackdropTemplate")
	tip:SetFrameStrata("TOOLTIP")
	tip:SetClampedToScreen(true)
	tip:SetWidth(TIP_W)
	tip:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	tip:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
	tip:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
	tip:Hide()

	tip.title = tip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	tip.title:SetPoint("TOPLEFT", 10, -10)
	tip.title:SetPoint("RIGHT", -10, 0)
	tip.title:SetJustifyH("LEFT")
	tip.subtitle = tip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	tip.subtitle:SetPoint("TOPLEFT", tip.title, "BOTTOMLEFT", 0, -2)
	tip.subtitle:SetPoint("RIGHT", -10, 0)
	tip.subtitle:SetJustifyH("LEFT")

	local chart = CreateFrame("Frame", nil, tip)
	chart:SetSize(CHART_W, CHART_H)
	chart:SetPoint("TOPLEFT", tip.subtitle, "BOTTOMLEFT", AXIS_W, -10)
	local bg = chart:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, 0.04)
	tip.chart = chart
	tip.grid, tip.yLabels = {}, {}
	for i = 1, 3 do
		local line = chart:CreateTexture(nil, "BORDER")
		line:SetColorTexture(1, 1, 1, i == 1 and 0.25 or 0.08)
		line:SetHeight(1)
		tip.grid[i] = line
		local label = tip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetJustifyH("RIGHT")
		label:SetWidth(AXIS_W - 6)
		tip.yLabels[i] = label
	end
	tip.xLabels = {}
	for i = 1, 3 do
		local label = tip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		tip.xLabels[i] = label
	end
	tip.xLabels[1]:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, -3)
	tip.xLabels[2]:SetPoint("TOP", chart, "BOTTOM", 0, -3)
	tip.xLabels[3]:SetPoint("TOPRIGHT", chart, "BOTTOMRIGHT", 0, -3)
	tip.lines, tip.dots, tip.legend = {}, {}, {}
	tip.footer = tip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	tip.footer:SetJustifyH("LEFT")
	tip.footer:SetWidth(TIP_W - 20)
end

local function TipLine(i)
	local line = tip.lines[i]
	if not line then
		line = tip.chart:CreateLine(nil, "ARTWORK")
		line:SetThickness(2)
		tip.lines[i] = line
	end
	line:Show()
	return line
end

local function TipDot(i)
	local dot = tip.dots[i]
	if not dot then
		dot = tip.chart:CreateTexture(nil, "OVERLAY")
		dot:SetSize(4, 4)
		tip.dots[i] = dot
	end
	dot:Show()
	return dot
end

local function TipLegend(i)
	local row = tip.legend[i]
	if not row then
		row = CreateFrame("Frame", nil, tip)
		row:SetSize(TIP_W - 20, 14)
		row.swatch = row:CreateTexture(nil, "ARTWORK")
		row.swatch:SetSize(10, 3)
		row.swatch:SetPoint("LEFT", 0, 0)
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.name:SetPoint("LEFT", 16, 0)
		row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.value:SetPoint("RIGHT", 0, 0)
		row.value:SetJustifyH("RIGHT")
		tip.legend[i] = row
	end
	row:Show()
	return row
end

local function DeltaText(n, days)
	local text = L["%s en %d j"]:format((n > 0 and "+" or "") .. Number(n), days)
	return (n > 0 and "|cff7fff7f" or "|cff999999") .. text .. "|r"
end

-- Infobulle d'une statistique : une courbe en escalier par personnage (couleur de sa classe), du
-- premier relevé à aujourd'hui ; légende avec la valeur actuelle et les écarts sur 7 et 30 jours.
local function ShowStatTip(row, item)
	if not tip then
		BuildTip()
	end
	tip.title:SetText(item.name)
	tip.subtitle:SetText(item.category or "")

	local series = {}
	local first, since
	local vmin, vmax
	for _, key in ipairs(Characters()) do
		local s = data[key].s[item.stat]
		if s and #s.d > 0 then
			series[#series + 1] = { key = key, s = s, since = data[key].since }
			first = math.min(first or s.d[1], s.d[1])
			since = math.min(since or data[key].since or s.d[1], data[key].since or s.d[1])
			for _, v in ipairs(s.v) do
				vmin, vmax = math.min(vmin or v, v), math.max(vmax or v, v)
			end
		end
	end
	table.sort(series, function(a, b)
		return Last(a.s) > Last(b.s)
	end)

	for _, line in ipairs(tip.lines) do
		line:Hide()
	end
	for _, dot in ipairs(tip.dots) do
		dot:Hide()
	end
	for _, legend in ipairs(tip.legend) do
		legend:Hide()
	end

	local today = Today()
	first = first or today
	local t0, t1 = DayTime(first), DayTime(today) + DAY
	if t1 - t0 < 2 * DAY then
		t0 = t1 - 2 * DAY
	end
	vmin, vmax = vmin or 0, vmax or 1
	if vmin == vmax then
		vmin = math.max(0, vmin - 1)
		vmax = vmax + 1
	end
	local function X(day)
		return (DayTime(day) - t0) / (t1 - t0) * CHART_W
	end
	local function Y(v)
		return 4 + (v - vmin) / (vmax - vmin) * (CHART_H - 8)
	end

	local mid = vmin + (vmax - vmin) / 2
	for i, v in ipairs({ vmin, mid, vmax }) do
		tip.grid[i]:ClearAllPoints()
		tip.grid[i]:SetPoint("BOTTOMLEFT", tip.chart, "BOTTOMLEFT", 0, Y(v))
		tip.grid[i]:SetPoint("BOTTOMRIGHT", tip.chart, "BOTTOMRIGHT", 0, Y(v))
		tip.yLabels[i]:SetPoint("RIGHT", tip.chart, "BOTTOMLEFT", -6, Y(v))
		tip.yLabels[i]:SetText(Number(math.floor(v + 0.5)))
	end
	tip.xLabels[1]:SetText(date(L["%d/%m"], t0))
	tip.xLabels[2]:SetText(date(L["%d/%m"], t0 + (t1 - t0) / 2))
	tip.xLabels[3]:SetText(date(L["%d/%m"], t1 - DAY))

	local nLines, nDots = 0, 0
	local function Segment(x1, y1, x2, y2, r, g, b)
		nLines = nLines + 1
		local line = TipLine(nLines)
		line:SetColorTexture(r, g, b, 0.95)
		line:SetStartPoint("BOTTOMLEFT", tip.chart, x1, y1)
		line:SetEndPoint("BOTTOMLEFT", tip.chart, x2, y2)
	end
	local previous = tip.chart
	for index, entry in ipairs(series) do
		local r, g, b = ClassColor(entry.key)
		local d, v = entry.s.d, entry.s.v
		for i = 1, #d do
			local x1, y1 = X(d[i]), Y(v[i])
			local x2 = d[i + 1] and X(d[i + 1]) or CHART_W
			if x2 > x1 then
				Segment(x1, y1, x2, y1, r, g, b)
			end
			if d[i + 1] then
				Segment(x2, y1, x2, Y(v[i + 1]), r, g, b)
			end
			nDots = nDots + 1
			local dot = TipDot(nDots)
			dot:SetColorTexture(r, g, b, 1)
			dot:SetPoint("CENTER", tip.chart, "BOTTOMLEFT", x1, y1)
		end
		local legend = TipLegend(index)
		legend.swatch:SetColorTexture(r, g, b, 1)
		legend.name:SetText(ShortName(entry.key))
		legend.value:SetText(Number(Last(entry.s)) .. "   "
			.. DeltaText(Last(entry.s) - ValueAt(entry.s, AddDays(today, -7), entry.since), 7) .. "  "
			.. DeltaText(Last(entry.s) - ValueAt(entry.s, AddDays(today, -30), entry.since), 30))
		legend:ClearAllPoints()
		if index == 1 then
			legend:SetPoint("TOPLEFT", tip.chart, "BOTTOMLEFT", -AXIS_W, -18)
		else
			legend:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -2)
		end
		previous = legend
	end
	tip.footer:ClearAllPoints()
	tip.footer:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", previous == tip.chart and -AXIS_W or 0,
		previous == tip.chart and -18 or -6)
	local sinceText = L["Suivi depuis le %s."]:format(date(L["%d/%m/%Y"], DayTime(since or today) + 12 * 3600))
	if #series == 0 or (first == today and since == today) then
		sinceText = sinceText .. " " .. L["La courbe se remplira au fil des jours."]
	end
	tip.footer:SetText(sinceText)

	local height = 10 + tip.title:GetStringHeight() + 2 + tip.subtitle:GetStringHeight() + 10 + CHART_H + 18
		+ #series * 16 + 6 + tip.footer:GetStringHeight() + 12
	tip:SetHeight(height)
	tip:ClearAllPoints()
	local right = row:GetRight() or 0
	if right + TIP_W + 8 < (UIParent:GetRight() or 0) then
		tip:SetPoint("TOPLEFT", row, "TOPRIGHT", 8, 0)
	else
		tip:SetPoint("TOPRIGHT", row, "TOPLEFT", -8, 0)
	end
	tip:Show()
end

local function HideStatTip()
	if tip then
		tip:Hide()
	end
end

-- LISTE -------------------------------------------------------------------------------------------

local function Extent(_, item)
	return item.header and ROW_H[item.header] or STAT_H
end

local function Setup(row)
	row.ready = true
	local hover = row:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.06)
	row.rule = row:CreateTexture(nil, "BACKGROUND")
	row.rule:SetHeight(1)
	row.rule:SetPoint("BOTTOMLEFT", 2, 1)
	row.rule:SetPoint("BOTTOMRIGHT", -2, 1)
	row.mark = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.cols = {}
	row:SetScript("OnClick", function(self)
		local item = self.item
		if item and item.header then
			local closed = Settings().statsClosed
			closed[item.id] = not closed[item.id] or nil
			ns.RefreshStats()
		end
	end)
	row:SetScript("OnEnter", function(self)
		if self.item and self.item.stat then
			ShowStatTip(self, self.item)
		end
	end)
	row:SetScript("OnLeave", HideStatTip)
end

local function Column(row, i)
	local col = row.cols[i]
	if not col then
		col = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		col:SetJustifyH("RIGHT")
		col:SetWidth(COL_W - 6)
		row.cols[i] = col
	end
	col:Show()
	return col
end

local function Apply(row, item)
	row.item = item
	for _, col in ipairs(row.cols) do
		col:Hide()
	end
	local indent = ((item.depth or 1) - 1) * INDENT
	row.mark:ClearAllPoints()
	row.name:ClearAllPoints()
	if item.header then
		local closed = Settings().statsClosed[item.id] and (searchBox:GetText() == "")
		row.mark:SetText(closed and "+" or "-")
		row.mark:SetPoint("LEFT", 6 + indent, 0)
		row.mark:Show()
		row.name:SetFontObject(item.header == 1 and "GameFontNormal" or "GameFontNormalSmall")
		row.name:SetPoint("LEFT", 20 + indent, 0)
		row.name:SetPoint("RIGHT", -6, 0)
		row.name:SetText(item.name)
		row.rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], item.header == 1 and 0.35 or 0.12)
		row.rule:Show()
		return
	end
	row.mark:Hide()
	row.rule:Hide()
	row.name:SetFontObject("GameFontHighlightSmall")
	row.name:SetPoint("LEFT", 20 + indent, 0)
	row.name:SetPoint("RIGHT", -(#columns * COL_W) - 4, 0)
	row.name:SetText(item.name)
	for i, column in ipairs(columns) do
		local col = Column(row, i)
		col:ClearAllPoints()
		col:SetPoint("RIGHT", -((#columns - i) * COL_W) - 4, 0)
		local value
		if column.delta then
			value = item.delta
			col:SetText(value > 0 and ("|cff7fff7f+" .. Number(value) .. "|r") or "|cff666666–|r")
		else
			if column.total then
				value = 0
				for _, v in pairs(item.values) do
					value = value + v
				end
			else
				value = item.values[column.key] or 0
			end
			col:SetText(value > 0 and Number(value) or "|cff666666–|r")
		end
	end
end

-- Colonnes selon la largeur : un personnage par colonne si le nom garde NAME_MIN px, sinon « Tous ».
local function LayoutColumns(keys)
	wipe(columns)
	local width = panel:GetWidth() - 30
	if width - (#keys + 1) * COL_W >= NAME_MIN or #keys <= 1 then
		for _, key in ipairs(keys) do
			columns[#columns + 1] = { key = key, label = ShortName(key) }
		end
	else
		columns[#columns + 1] = { total = true, label = L["Tous"] }
	end
	columns[#columns + 1] = { delta = true, label = L["%d j"]:format(DELTA_DAYS) }
	for _, label in ipairs(columnHeader.labels) do
		label:Hide()
	end
	for i, column in ipairs(columns) do
		local label = columnHeader.labels[i]
		if not label then
			label = columnHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			label:SetJustifyH("RIGHT")
			label:SetWidth(COL_W - 6)
			label:SetWordWrap(false)
			columnHeader.labels[i] = label
		end
		label:ClearAllPoints()
		label:SetPoint("RIGHT", -((#columns - i) * COL_W) - 4 - 14, 0) -- aligné sur les lignes, barre de défilement visible
		label:SetText(column.label)
		label:Show()
	end
end

function ns.BuildStats(parent)
	panel = P.CreatePanel(parent, "")
	panel.header:SetText("")

	searchBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	searchBox:SetSize(160, 18)
	searchBox:SetPoint("TOPLEFT", 14, -7)
	searchBox:SetAutoFocus(false)
	searchBox.placeholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	searchBox.placeholder:SetPoint("LEFT", 2, 0)
	searchBox.placeholder:SetText(L["Rechercher..."])
	searchBox:SetScript("OnTextChanged", function(self)
		self.placeholder:SetShown(self:GetText() == "")
		ns.RefreshStats()
	end)
	searchBox:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	searchBox:SetScript("OnEnterPressed", searchBox.ClearFocus)
	if P.SkinEditBox then
		P.SkinEditBox(searchBox)
	end

	countText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	countText:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
	countText:SetPoint("RIGHT", -10, 0)
	countText:SetJustifyH("RIGHT")

	columnHeader = CreateFrame("Frame", nil, panel)
	columnHeader:SetPoint("TOPLEFT", 6, -30)
	columnHeader:SetPoint("TOPRIGHT", -6, -30)
	columnHeader:SetHeight(16)
	columnHeader.labels = {}
	local statLabel = columnHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	statLabel:SetPoint("LEFT", 20, 0)
	statLabel:SetText(L["Statistique"])

	local top = 48
	local scrollBox = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
	local scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtentCalculator(Extent)
	view:SetElementInitializer("Button", function(row, item)
		if not row.ready then
			Setup(row)
		end
		Apply(row, item)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	local topLeft = CreateAnchor("TOPLEFT", panel, "TOPLEFT", 6, -top)
	ScrollUtil.AddManagedScrollBarVisibilityBehavior(scrollBox, scrollBar,
		{ topLeft, CreateAnchor("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 6) },
		{ topLeft, CreateAnchor("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 6) })
	if P.SkinScrollBar then
		P.SkinScrollBar(scrollBar)
	end
	list = scrollBox

	panel.emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	panel.emptyText:SetPoint("TOPLEFT", 12, -top - 6)
	panel.emptyText:SetPoint("RIGHT", -12, 0)
	panel.emptyText:SetJustifyH("LEFT")

	panel:HookScript("OnSizeChanged", function()
		if panel:IsShown() then
			ns.RefreshStats()
		end
	end)
	panel:HookScript("OnHide", HideStatTip)
	if P.SkinPanel then
		P.SkinPanel(panel)
	end
	return panel
end

-- Remplit la vue (si elle est affichée).
function ns.RefreshStats()
	if not panel or not panel:IsVisible() then
		return
	end
	local keys = Characters()
	LayoutColumns(keys)
	local items = BuildItems(keys)
	local shown = 0
	for _, item in ipairs(items) do
		if item.stat then
			shown = shown + 1
		end
	end
	local since
	for _, key in ipairs(keys) do
		local s = data[key].since
		since = s and math.min(since or s, s) or since
	end
	countText:SetText(since and L["%d personnage(s), suivi depuis le %s"]:format(#keys,
		date(L["%d/%m/%Y"], DayTime(since) + 12 * 3600)) or "")
	if not Categories() then
		panel.emptyText:SetText(L["Statistiques indisponibles dans ce client."])
	elseif searchBox:GetText() ~= "" then
		panel.emptyText:SetText(L["Aucune statistique ne correspond à la recherche."])
	else
		panel.emptyText:SetText(L["Aucune statistique relevée pour l'instant."])
	end
	panel.emptyText:SetShown(#items == 0)
	list:SetDataProvider(CreateDataProvider(items), ScrollBoxConstants.RetainScrollPosition)
end
