-- Polypode Histoire: Frise — vue chronologique horizontale du journal (jour, semaine, mois, tous)

local _, ns = ...
local P = Polypode
local L = ns.L

-- VUE « Frise » de la fenêtre Histoire (boutons Liste / Frise en haut à gauche) : axe horizontal
-- sur une période (Jour : cadré sur la plage jouée ; Semaine : du lundi au dimanche ; Mois ; Tous :
-- tout le journal), piste des événements (icône, texte court, infobulle détaillée, clic : le jour
-- dans la liste) et une piste de sessions par personnage (couleur de classe). Clic ailleurs sur la
-- frise (zones, barres) : en Mois, la semaine cliquée ; en Semaine, le jour cliqué. Mêmes règles que le
-- site Histoire (src/timeline.js) : plus la période est longue, moins on montre de détails (poids
-- WEIGHT, seuil MIN_WEIGHT) ; une catégorie cochée en bas de la fenêtre montre tous ses
-- événements ; événements voisins à moins de CLUSTER_PX regroupés (compteur, icône et texte du
-- plus marquant). La frise suit la largeur de la fenêtre (regroupement refait au redimensionnement).
-- Journées : celles du journal (minuit, ns.DayOf). Éléments graphiques recyclés (pools).

local H = ns.H -- outils de Histoire.lua (chargé avant ce fichier)

local SCALES = {
	{ key = "jour", label = L["Jour"] },
	{ key = "semaine", label = L["Semaine"] },
	{ key = "mois", label = L["Mois"] },
	{ key = "tous", label = L["Tous"] },
}
local WEIGHT = {
	boss = 3, mplus = 3, lvl = 3, mount = 3,
	ach = 2, dng = 2, renown = 2, guild = 2,
	delve = 1, toy = 1, pet = 1, rep = 1, ilvl = 1, friend = 1, club = 1, grp = 1,
	enter = 0,
}
local MIN_WEIGHT = { jour = 0, semaine = 1, mois = 2, tous = 3 }
local KIND_LABELS = {
	boss = L["boss de raid vaincu"], mplus = L["clé mythique+ terminée"], lvl = L["niveau atteint"],
	mount = L["monture obtenue"], ach = L["haut fait"], dng = L["donjon terminé"], renown = L["palier de renom"],
	guild = L["guilde rejointe ou quittée"], delve = L["gouffre (ou section) terminé"], toy = L["jouet"],
	pet = L["mascotte"], rep = L["rang de réputation"], ilvl = L["niveau d'objet"], friend = L["ami ajouté ou retiré"],
	club = L["communauté rejointe ou quittée"], grp = L["équipe groupée"], enter = L["entrée dans une instance"],
}
-- Icônes du jeu par type et icône des patchs : celles de Histoire.lua (liste et frise).
local ICONS = H.ICONS
local PATCH_ICON = H.PATCH_ICON

local CLUSTER_PX = 30 -- en dessous : événements voisins regroupés
local LABEL_PX = 100 -- voisins de la même rangée au moins à cette distance : texte court affiché
local TOOLTIP_MAX = 8
local ICON = 22
local LABEL_H = 13
local PATCH_STRIP = 20 -- bande des icônes de patch, au-dessus des événements
local AXIS_H = 14
local TOP_BAR = 30 -- barre du haut (chevrons, échelles)
local LANE_MAX = 26 -- hauteur maximale d'une piste de présence (px)
local TOTALS_MIN_H = 22 -- vue Semaine : total du jour écrit sous les barres à partir de cette hauteur
local JOUR_MARGIN = 1800 -- vue Jour : marge autour de la plage jouée (s)
local JOUR_MIN_SPAN = 3 * 3600
local PATCH_RGB = { 0.25, 1, 0.25 }
-- Mois et jours abrégés : une seule clé chacun, découpée aux espaces (en français, « mars » abrégé
-- et « mars » entier sont la même clé, que l'anglais distingue : Mar / March).
local MONTHS_SHORT = { strsplit(" ", L["janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc."]) }
local WEEKDAYS_SHORT = { strsplit(" ", L["dim. lun. mar. mer. jeu. ven. sam."]) }

local panel, area, track, periodText, emptyText
local scaleButtons = {}
local state = { scale = "semaine" } -- anchor : jour d'ancrage de la période (nil : dernier jour joué)
local renderPending
local currentZones = {} -- zones cliquables du dernier rendu (BuildModel)

-- DATES -------------------------------------------------------------------------------------------

local function DayParts(day)
	return tonumber(day:sub(1, 4)), tonumber(day:sub(6, 7)), tonumber(day:sub(9, 10))
end

-- Minuit (heure locale) du jour.
local function DayStart(day)
	local y, m, d = DayParts(day)
	return time({ year = y, month = m, day = d, hour = 0 })
end

local function AddDays(day, n)
	local y, m, d = DayParts(day)
	return date("%Y-%m-%d", time({ year = y, month = m, day = d + n, hour = 12 }))
end

local function AddMonths(day, n)
	local y, m = DayParts(day)
	m = m - 1 + n
	return string.format("%04d-%02d-01", y + math.floor(m / 12), m % 12 + 1)
end

-- 0 = dimanche ... 6 = samedi.
local function Weekday(day)
	local y, m, d = DayParts(day)
	return tonumber(date("%w", time({ year = y, month = m, day = d, hour = 12 })))
end

local function DayShort(day)
	local _, m, d = DayParts(day)
	return WEEKDAYS_SHORT[Weekday(day) + 1] .. " " .. d .. " " .. MONTHS_SHORT[m]
end

local function SortedDays()
	local days = {}
	for day in pairs(ns.GetDays()) do
		days[#days + 1] = day
	end
	table.sort(days)
	return days
end

-- Période : { startKey, endKey (exclu), start, stop } en jours du journal et en secondes.
local function Period(scale, anchor, days)
	local startKey, endKey
	if scale == "jour" then
		startKey, endKey = anchor, AddDays(anchor, 1)
	elseif scale == "semaine" then
		startKey = AddDays(anchor, -((Weekday(anchor) + 6) % 7)) -- lundi
		endKey = AddDays(startKey, 7)
	elseif scale == "mois" then
		startKey = anchor:sub(1, 7) .. "-01"
		endKey = AddMonths(startKey, 1)
	else
		startKey = days[1] or anchor
		endKey = AddDays(days[#days] or anchor, 1)
	end
	return { startKey = startKey, endKey = endKey, start = DayStart(startKey), stop = DayStart(endKey) }
end

local function ShiftAnchor(scale, anchor, step)
	if scale == "jour" then
		return AddDays(anchor, step)
	elseif scale == "semaine" then
		return AddDays(anchor, 7 * step)
	elseif scale == "mois" then
		return AddMonths(anchor, step)
	end
	return anchor
end

local function PeriodLabel(scale, period)
	local y, m, d = DayParts(period.startKey)
	local months, inText = H.MONTHS, H.MONTHS_IN_TEXT
	if scale == "jour" then
		return L["%s %d %s %d"]:format(H.WEEKDAYS[Weekday(period.startKey) + 1], d, inText[m], y)
	elseif scale == "mois" then
		return months[m] .. " " .. y
	end
	local ly, lm, ld = DayParts(AddDays(period.endKey, -1))
	if scale == "semaine" then
		if m == lm then
			return L["Semaine du %d au %d %s %d"]:format(d, ld, inText[lm], ly)
		end
		return L["Semaine du %d %s au %d %s %d"]:format(d, inText[m], ld, inText[lm], ly)
	end
	return L["Du %d %s %d au %d %s %d"]:format(d, inText[m], y, ld, inText[lm], ly)
end

-- DONNÉES -----------------------------------------------------------------------------------------

-- Sessions { key, start, stop, open } : « in » → « out » du même personnage ; sans « out », jusqu'au
-- dernier événement connu du personnage (open).
local function Intervals(days)
	local list, lastIn, lastSeen = {}, {}, {}
	local store = ns.GetDays()
	local function close(key)
		local start = lastIn[key]
		list[#list + 1] = { key = key, start = start, stop = math.max(start, lastSeen[key] or start), open = true }
		lastIn[key] = nil
	end
	for _, day in ipairs(days) do
		for _, event in ipairs(store[day]) do
			local time, key, kind = ns.Parse(event)
			if time and key then
				if kind == "in" then
					if lastIn[key] then
						close(key)
					end
					lastIn[key] = time
				elseif kind == "out" and lastIn[key] then
					list[#list + 1] = { key = key, start = lastIn[key], stop = time, open = false }
					lastIn[key] = nil
				end
				lastSeen[key] = time
			end
		end
	end
	for key in pairs(lastIn) do
		close(key)
	end
	return list
end

-- Temps joué par jour et par personnage : played[jour][clé] = secondes, séances coupées à minuit.
local function PlayedByDay(sessions)
	local played = {}
	for _, s in ipairs(sessions) do
		local t = s.start
		while t < s.stop do
			local day = ns.DayOf(t)
			local nextStart = DayStart(AddDays(day, 1))
			local stop = math.min(s.stop, nextStart)
			played[day] = played[day] or {}
			played[day][s.key] = (played[day][s.key] or 0) + (stop - t)
			if nextStart <= t then
				break -- sécurité (changement d'heure mal lu) : pas de boucle sans fin
			end
			t = stop
		end
	end
	return played
end

-- Intensité d'une case de chaleur (racine : les petites parties restent visibles), 0 si rien.
local function HeatLevel(value, max)
	if not value or value <= 0 then
		return 0
	end
	return 0.18 + 0.82 * math.sqrt(value / math.max(max, 1))
end

-- Texte court sous l'icône (f[4] : premier champ après heure~clé~type).
local function ShortText(line)
	local f, n = line.fields, #line.keys > 1 and (" ×" .. #line.keys) or ""
	local kind = line.kind
	if kind == "lvl" then
		return L["Niv. %s"]:format(f[4] or "?")
	elseif kind == "ilvl" then
		return L["iLvl %s"]:format(f[4] or "?")
	elseif kind == "ach" then
		return L["Haut fait"] .. n
	elseif kind == "boss" or kind == "dng" or kind == "enter" then
		return f[4] or "?"
	elseif kind == "mplus" then
		return "+" .. (f[5] or "?") .. " " .. (f[4] or "")
	elseif kind == "delve" then
		return L["Gouffre"] .. ((f[5] and f[5] ~= "" and f[5] ~= "0") and (" " .. f[5]) or "")
	elseif kind == "renown" then
		return L["Renom %s"]:format(f[5] or "?")
	elseif kind == "rep" then
		return f[5] or L["Réputation"]
	elseif kind == "toy" or kind == "mount" or kind == "pet" then
		return (f[5] and f[5] ~= "") and f[5] or "?"
	elseif kind == "friend" or kind == "guild" or kind == "club" then
		return (f[5] == "+" and "+ " or "- ") .. (f[4] or "?")
	elseif kind == "grp" then
		return L["Équipe %s"]:format(f[4] or "?")
	end
	return kind
end

-- Modèle de la période : événements (positions en px sur la largeur de la piste), groupes,
-- sessions par personnage, graduations, patchs.
local function BuildModel(width)
	local settings = H.Settings()
	local days = SortedDays()
	local anchor = state.anchor or days[#days] or ns.DayOf(GetServerTime())
	state.anchor = anchor
	local period = Period(state.scale, anchor, days)
	local store = ns.GetDays()
	local durations = H.SessionDurations(store)
	local minWeight = next(settings.filters) and 0 or MIN_WEIGHT[state.scale]

	local items = {}
	for _, day in ipairs(days) do
		if day >= period.startKey and day < period.endKey then
			local kept = {}
			for _, event in ipairs(H.Filtered(store[day])) do
				local _, _, kind = ns.Parse(event)
				if kind ~= "in" and kind ~= "out" and (WEIGHT[kind] or 0) >= minWeight then
					kept[#kept + 1] = event
				end
			end
			for _, line in ipairs(H.DayLines(kept, durations)) do
				line.day = day
				line.weight = WEIGHT[line.kind] or 0
				items[#items + 1] = line
			end
		end
	end
	local sessions = {}
	local allSessions = Intervals(days)
	for _, s in ipairs(allSessions) do
		if s.stop >= period.start and s.start < period.stop then
			sessions[#sessions + 1] = s
		end
	end

	-- Vue Jour : cadrée sur la plage jouée (première à dernière activité, marge, heures pleines).
	local start, stop = period.start, period.stop
	if state.scale == "jour" and (#items > 0 or #sessions > 0) then
		local first, last = math.huge, -math.huge
		for _, item in ipairs(items) do
			first, last = math.min(first, item.time), math.max(last, item.time)
		end
		for _, s in ipairs(sessions) do
			first = math.min(first, math.max(s.start, period.start))
			last = math.max(last, math.min(s.stop, period.stop))
		end
		start = math.max(period.start, math.floor((first - JOUR_MARGIN) / 3600) * 3600)
		stop = math.min(period.stop, math.ceil((last + JOUR_MARGIN) / 3600) * 3600)
		if stop - start < JOUR_MIN_SPAN then
			stop = math.min(period.stop, start + JOUR_MIN_SPAN)
			start = math.max(period.start, stop - JOUR_MIN_SPAN)
		end
	end
	local span = math.max(stop - start, 1)
	local function x(t)
		return math.max(0, math.min(width, (t - start) / span * width))
	end

	table.sort(items, function(a, b)
		return a.time < b.time
	end)
	local clusters = {}
	for _, item in ipairs(items) do
		item.x = x(item.time)
		local last = clusters[#clusters]
		if last and item.x - last.first <= CLUSTER_PX then
			last.items[#last.items + 1] = item
		else
			clusters[#clusters + 1] = { first = item.x, items = { item } }
		end
	end
	for i, c in ipairs(clusters) do
		local sum, main = 0, c.items[1]
		for _, item in ipairs(c.items) do
			sum = sum + item.x
			if item.weight > main.weight then
				main = item
			end
		end
		c.x, c.main, c.row = sum / #c.items, main, (i - 1) % 2
	end
	for i, c in ipairs(clusters) do
		local nextGap = clusters[i + 2] and (clusters[i + 2].x - c.x) or math.huge
		local prevGap = clusters[i - 2] and (c.x - clusters[i - 2].x) or math.huge
		c.showLabel = math.min(nextGap, prevGap) >= LABEL_PX
	end

	-- Pistes de sessions, triées par temps joué.
	local lanesByKey, lanes = {}, {}
	for _, s in ipairs(sessions) do
		local lane = lanesByKey[s.key]
		if not lane then
			lane = { key = s.key, bars = {}, total = 0 }
			lanesByKey[s.key] = lane
			lanes[#lanes + 1] = lane
		end
		local from, to = math.max(s.start, start), math.min(s.stop, stop)
		if to >= from then
			lane.bars[#lane.bars + 1] = { session = s, x = x(from), w = math.max(x(to) - x(from), 2) }
			lane.total = lane.total + (to - from)
		end
	end
	-- Colonnes de présence : jours (Semaine, Mois) ou semaines du lundi (Tous) ; cases de chaleur par
	-- personnage (Mois, Tous : à la place des barres ; Semaine : fond discret sous les barres) et
	-- clic sur une case : l'échelle en dessous (Tous, Mois → semaine ; Semaine → jour).
	local columns = {}
	local function addColumn(first, stopKey, list)
		local x1, x2 = x(DayStart(first)), x(DayStart(stopKey))
		if x2 > x1 then
			local wd = Weekday(first)
			columns[#columns + 1] = { day = first, days = list, x = x1, w = x2 - x1,
				weekend = #list == 1 and (wd == 0 or wd == 6),
				zoom = state.scale == "semaine" and "jour" or "semaine" }
		end
	end
	if state.scale == "semaine" or state.scale == "mois" then
		local day = period.startKey
		while day < period.endKey do
			addColumn(day, AddDays(day, 1), { day })
			day = AddDays(day, 1)
		end
	elseif state.scale == "tous" then
		local monday = AddDays(period.startKey, -((Weekday(period.startKey) + 6) % 7))
		while monday < period.endKey do
			local list = {}
			for i = 0, 6 do
				list[#list + 1] = AddDays(monday, i)
			end
			addColumn(monday, AddDays(monday, 7), list)
			monday = AddDays(monday, 7)
		end
	end
	local heat = state.scale == "mois" or state.scale == "tous"
	local played = PlayedByDay(allSessions)
	local function playedIn(key, list)
		local sum = 0
		for _, d in ipairs(list) do
			local perChar = played[d]
			if perChar then
				if key then
					sum = sum + (perChar[key] or 0)
				else
					for k, v in pairs(perChar) do
						if lanesByKey[k] then
							sum = sum + v
						end
					end
				end
			end
		end
		return sum
	end
	local maxCell, maxSum = 0, 0
	local sum = #lanes > 1 and { cells = {}, total = 0 } or nil
	for _, lane in ipairs(lanes) do
		lane.cells = {}
		local total = 0
		for i, col in ipairs(columns) do
			lane.cells[i] = playedIn(lane.key, col.days)
			maxCell = math.max(maxCell, lane.cells[i])
			total = total + lane.cells[i]
		end
		if heat then
			lane.total = total -- temps joué dans la période (jours entiers)
		end
	end
	if sum then
		for i, col in ipairs(columns) do
			sum.cells[i] = playedIn(nil, col.days)
			maxSum = math.max(maxSum, sum.cells[i])
		end
		for _, lane in ipairs(lanes) do
			sum.total = sum.total + lane.total
		end
	end
	table.sort(lanes, function(a, b)
		return a.total > b.total
	end)

	-- Graduations.
	local ticks = {}
	if state.scale == "jour" then
		local every = span > 10 * 3600 and 2 or 1
		local t = math.ceil(start / 3600) * 3600
		while t <= stop do
			local hour = tonumber(date("%H", t))
			ticks[#ticks + 1] = { x = x(t), label = hour % every == 0 and L["%d h"]:format(hour) or nil, minor = hour % every ~= 0 }
			t = t + 3600
		end
	elseif state.scale == "semaine" or state.scale == "mois" then
		local day = period.startKey
		while day < period.endKey do
			local t = DayStart(day)
			local _, _, d = DayParts(day)
			local label
			if state.scale == "semaine" then
				label = DayShort(day)
			elseif d == 1 or d % 5 == 0 then
				label = tostring(d)
			end
			ticks[#ticks + 1] = { x = x(t), labelX = state.scale == "semaine" and x(t + 43200) or nil, label = label,
				minor = state.scale == "mois" and not label }
			day = AddDays(day, 1)
		end
	else
		local day = period.startKey
		while day < period.endKey do
			if Weekday(day) == 1 or day == period.startKey then
				ticks[#ticks + 1] = { x = x(DayStart(day)), label = DayShort(day) }
			end
			day = AddDays(day, 1)
		end
	end

	-- Zones cliquables : Mois → une par semaine (lundi à dimanche, rognée au mois) ; Semaine → une
	-- par jour. Clic : cette semaine, ce jour.
	local zones = {}
	if state.scale == "semaine" or state.scale == "mois" then
		local day = period.startKey
		while day < period.endKey do
			local stopKey = AddDays(day, 1)
			if state.scale == "mois" then
				stopKey = AddDays(day, 7 - (Weekday(day) + 6) % 7) -- lundi suivant
				if stopKey > period.endKey then
					stopKey = period.endKey
				end
			end
			local x1, x2 = x(DayStart(day)), x(DayStart(stopKey))
			zones[#zones + 1] = { day = day, last = AddDays(stopKey, -1), x = x1, w = x2 - x1,
				scale = state.scale == "mois" and "semaine" or "jour" }
			day = stopKey
		end
	end

	local patches = {}
	if H.IS_RETAIL and settings.showPatches then
		for day, name in pairs(H.PATCHES) do
			if day >= period.startKey and day < period.endKey then
				patches[#patches + 1] = { day = day, name = name, x = x(DayStart(day)) }
			end
		end
	end

	return { period = period, clusters = clusters, lanes = lanes, ticks = ticks, patches = patches, zones = zones,
		count = #items, columns = columns, heat = heat, sum = sum, maxCell = maxCell, maxSum = maxSum }
end

-- RECYCLAGE DES ÉLÉMENTS --------------------------------------------------------------------------

local pools = {}

local function Pool(name, create)
	local pool = pools[name]
	if not pool then
		pool = { used = 0, items = {}, create = create }
		pools[name] = pool
	end
	return pool
end

local function Acquire(pool)
	pool.used = pool.used + 1
	local item = pool.items[pool.used]
	if not item then
		item = pool.create()
		pool.items[pool.used] = item
	end
	item:Show()
	return item
end

local function ReleaseAll()
	for _, pool in pairs(pools) do
		for i = 1, #pool.items do
			pool.items[i]:Hide()
		end
		pool.used = 0
	end
end

local SetIcon = H.SetIcon

-- INFOBULLES ET ACTIONS ---------------------------------------------------------------------------

local function TimeLabel(t)
	return date("%H:%M", t)
end

local function MarkerTooltip(self)
	local cluster = self.cluster
	if not cluster then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	local n = #cluster.items
	GameTooltip:AddLine(n > 1 and L["%d événements"]:format(n) or KIND_LABELS[cluster.main.kind] or cluster.main.kind)
	for i = 1, math.min(n, TOOLTIP_MAX) do
		local line = cluster.items[i]
		local times = {}
		for j, key in ipairs(line.keys) do
			times[#times + 1] = (#line.keys > 1 and (H.CharName(key) .. " ") or "") .. TimeLabel(line.times[j])
		end
		GameTooltip:AddLine(DayShort(line.day) .. " · " .. table.concat(times, ", "), 0.6, 0.6, 0.6)
		if GameTooltip.AddTexture then
			GameTooltip:AddTexture("Interface\\Icons\\" .. (ICONS[line.kind] or "INV_Misc_QuestionMark"))
		end
		GameTooltip:AddLine(H.EventText(line), 1, 1, 1, true)
	end
	if n > TOOLTIP_MAX then
		GameTooltip:AddLine(L["... et %d autre(s)"]:format(n - TOOLTIP_MAX), 0.6, 0.6, 0.6)
	end
	GameTooltip:AddLine(L["Clic : voir ce jour dans la liste"], 0.7, 0.7, 0.7)
	H.ShowTooltip()
end

local function BarTooltip(self)
	local s = self.session
	if not s then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:AddLine(H.CharName(s.key))
	-- Pas de flèche « → » : absente de la police du jeu (carré vide).
	GameTooltip:AddLine(L["%s, de %s à %s"]:format(date(L["%d/%m"], s.start), TimeLabel(s.start), TimeLabel(s.stop))
		.. (s.open and " " .. L["(fin non notée)"] or "") .. " · " .. H.DurationText(s.stop - s.start), 1, 1, 1)
	if #currentZones > 0 then
		GameTooltip:AddLine(state.scale == "mois" and L["Clic : afficher cette semaine"] or L["Clic : afficher ce jour"],
			0.7, 0.7, 0.7)
	end
	H.ShowTooltip()
end

-- Zones (semaines du mois, jours de la semaine, currentZones) : clic → la frise sur cette semaine
-- ou ce jour.
local function ZoomTo(zone)
	state.scale, state.anchor = zone.scale, zone.day
	ns.RefreshFrise()
end

-- Zone sous le curseur (clic sur une barre de session, posée par-dessus les zones).
local function ZoneAtCursor()
	local left = track:GetLeft()
	if not left then
		return
	end
	local cx = GetCursorPosition() / track:GetEffectiveScale() - left
	for _, zone in ipairs(currentZones) do
		if cx >= zone.x and cx < zone.x + zone.w then
			return zone
		end
	end
end

local function ZoneTooltip(self)
	local zone = self.zone
	if not zone then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
	GameTooltip:AddLine(PeriodLabel(zone.scale, Period(zone.scale, zone.day)))
	GameTooltip:AddLine(zone.scale == "jour" and L["Clic : afficher ce jour"] or L["Clic : afficher cette semaine"],
		0.7, 0.7, 0.7)
	H.ShowTooltip()
end

local function PatchTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:AddLine(DayShort(self.patch.day))
	GameTooltip:AddLine(self.patch.name, PATCH_RGB[1], PATCH_RGB[2], PATCH_RGB[3], true)
	H.ShowTooltip()
end

-- Importance des événements : poids, seuil de chaque échelle, règle du filtre (bouton « ? »).
local function ImportanceText()
	local byWeight, weights = {}, {}
	for kind, weight in pairs(WEIGHT) do
		if not byWeight[weight] then
			byWeight[weight] = {}
			weights[#weights + 1] = weight
		end
		table.insert(byWeight[weight], KIND_LABELS[kind] or kind)
	end
	table.sort(weights, function(a, b)
		return a > b
	end)
	local lines = { "|cff40ff40" .. L["Un filtre coché prend la main :"] .. "|r "
		.. L["une catégorie cochée en bas de la fenêtre montre tous ses événements, quelle que soit l'échelle."], "",
		"|cffffd200" .. L["Poids des événements"] .. "|r" }
	for _, w in ipairs(weights) do
		table.sort(byWeight[w])
		lines[#lines + 1] = L["%s : %s"]:format("|cffffd200" .. w .. "|r", table.concat(byWeight[w], ", "))
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "|cffffd200" .. L["Seuil par échelle"] .. "|r"
	for _, scale in ipairs(SCALES) do
		lines[#lines + 1] = L["%s : poids %d et plus"]:format(scale.label, MIN_WEIGHT[scale.key])
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = L["Connexions : montrées par les barres de session. Événements trop proches : regroupés "
		.. "(compteur), icône et texte du plus marquant."]
	lines[#lines + 1] = ""
	lines[#lines + 1] = L["Présence : barres de séance en Jour et Semaine (total du jour dessous s'il y a la place) ; "
		.. "cases en Mois (par jour) et Tous (par semaine), plus foncées quand on a plus joué ; ligne « Tous » : tous "
		.. "les personnages."]
	return table.concat(lines, "\n")
end

-- RENDU -------------------------------------------------------------------------------------------

local function CreateMarker()
	local button = CreateFrame("Button", nil, track)
	button:SetSize(ICON, ICON)
	button.border = button:CreateTexture(nil, "BACKGROUND")
	button.border:SetPoint("TOPLEFT", -1, 1)
	button.border:SetPoint("BOTTOMRIGHT", 1, -1)
	button.border:SetColorTexture(0, 0, 0, 0.9)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button.badge = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	button.badge:SetPoint("TOPRIGHT", 5, 4)
	button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.label:SetPoint("TOP", button, "BOTTOM", 0, -1)
	button.label:SetWidth(LABEL_PX - 8)
	button.label:SetWordWrap(false)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetScript("OnEnter", MarkerTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnClick", function(self)
		if self.cluster then
			H.OpenDay(self.cluster.main.day)
		end
	end)
	return button
end

local function CreateBar()
	local bar = CreateFrame("Button", nil, track)
	bar.fill = bar:CreateTexture(nil, "ARTWORK")
	bar.fill:SetAllPoints()
	bar:SetScript("OnEnter", BarTooltip)
	bar:SetScript("OnLeave", GameTooltip_Hide)
	bar:SetScript("OnClick", function()
		local zone = ZoneAtCursor()
		if zone then
			ZoomTo(zone)
		end
	end)
	return bar
end

-- Case de chaleur : infobulle (qui, quand, temps joué) ; clic → l'échelle en dessous.
local function CellTooltip(self)
	local info = self.info
	if not info then
		return
	end
	local col = info.column
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:AddLine(info.label)
	GameTooltip:AddLine(#col.days == 1 and DayShort(col.day) or PeriodLabel("semaine", Period("semaine", col.day)),
		0.6, 0.6, 0.6)
	if (info.value or 0) > 0 then
		GameTooltip:AddLine(H.DurationText(info.value), 1, 1, 1)
	end
	GameTooltip:AddLine(col.zoom == "jour" and L["Clic : afficher ce jour"] or L["Clic : afficher cette semaine"],
		0.7, 0.7, 0.7)
	H.ShowTooltip()
end

local function CreateCell()
	local cell = CreateFrame("Button", nil, track)
	cell.fill = cell:CreateTexture(nil, "ARTWORK")
	cell.fill:SetAllPoints()
	cell:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
	cell:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.12)
	cell:SetScript("OnEnter", CellTooltip)
	cell:SetScript("OnLeave", GameTooltip_Hide)
	cell:SetScript("OnClick", function(self)
		if self.info then
			ZoomTo({ scale = self.info.column.zoom, day = self.info.column.day })
		end
	end)
	return cell
end

local function CreateZone()
	local button = CreateFrame("Button", nil, track)
	button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
	button:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
	button:SetScript("OnEnter", ZoneTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnClick", function(self)
		if self.zone then
			ZoomTo(self.zone)
		end
	end)
	return button
end

local function CreatePatchMark()
	local button = CreateFrame("Button", nil, track)
	button:SetSize(16, 16)
	button.border = button:CreateTexture(nil, "BACKGROUND")
	button.border:SetPoint("TOPLEFT", -2, 2)
	button.border:SetPoint("BOTTOMRIGHT", 2, -2)
	button.border:SetColorTexture(PATCH_RGB[1], PATCH_RGB[2], PATCH_RGB[3], 1)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	SetIcon(button.icon, PATCH_ICON)
	button:SetScript("OnEnter", PatchTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

local function CreateLine()
	return track:CreateTexture(nil, "BACKGROUND")
end

local function CreateText()
	local text = area:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetWordWrap(false)
	return text
end

local function Render()
	renderPending = nil
	if not panel or not panel:IsVisible() then
		return
	end
	ReleaseAll()
	local markers, bars = Pool("marker", CreateMarker), Pool("bar", CreateBar)
	local marks, lines, texts = Pool("patch", CreatePatchMark), Pool("line", CreateLine), Pool("text", CreateText)
	local zones = Pool("zone", CreateZone)

	-- Colonne des noms : largeur du nom le plus long (nom et temps joué sur une ligne).
	local probe = Acquire(texts)
	local width = area:GetWidth()
	local model = BuildModel(math.max(width - 160, 50)) -- première passe : noms à mesurer
	local nameWidth = 70
	for _, lane in ipairs(model.lanes) do
		probe:SetText(H.CharName(lane.key) .. "  " .. H.DurationText(lane.total))
		nameWidth = math.max(nameWidth, probe:GetStringWidth() + 12)
	end
	if model.sum then
		probe:SetText(L["Tous"] .. "  " .. H.DurationText(model.sum.total))
		nameWidth = math.max(nameWidth, probe:GetStringWidth() + 12)
	end
	probe:Hide()
	local trackWidth = math.max(width - nameWidth - 8, 50)
	model = BuildModel(trackWidth)
	currentZones = model.zones

	periodText:SetText(PeriodLabel(state.scale, model.period))
	for _, button in ipairs(scaleButtons) do
		if button.scale == state.scale then
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
	end
	panel.prevButton:SetEnabled(state.scale ~= "tous")
	panel.nextButton:SetEnabled(state.scale ~= "tous")

	if model.count == 0 and #model.lanes == 0 then
		emptyText:Show()
		track:Hide()
		return
	end
	emptyText:Hide()
	track:Show()
	track:ClearAllPoints()
	track:SetPoint("TOPLEFT", area, "TOPLEFT", nameWidth, 0)
	track:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", 0, 0)

	-- Hauteurs : bande des patchs, deux rangées d'événements, pistes (ligne « Tous » comprise), axe.
	local height = area:GetHeight()
	local strip = #model.patches > 0 and PATCH_STRIP or 0
	local rowH = ICON + LABEL_H + 4
	local eventsH = strip + 2 * rowH + 4
	local rows = {}
	if model.sum then
		rows[1] = { sum = model.sum, total = model.sum.total, cells = model.sum.cells }
	end
	for _, lane in ipairs(model.lanes) do
		rows[#rows + 1] = lane
	end
	local laneCount = math.max(#rows, 1)
	local laneH = math.max(8, math.min(LANE_MAX, math.floor((height - eventsH - AXIS_H) / laneCount)))
	local lanesTop = eventsH
	local axisTop = lanesTop + laneH * #rows

	-- Libellé de la piste des événements.
	local evLabel = Acquire(texts)
	evLabel:ClearAllPoints()
	evLabel:SetPoint("LEFT", area, "TOPLEFT", 0, -(strip + rowH))
	evLabel:SetText("|cff999999" .. L["Événements"] .. "|r")

	-- Graduations (traits sur toute la hauteur) et libellés de l'axe.
	for _, tick in ipairs(model.ticks) do
		local line = Acquire(lines)
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", track, "TOPLEFT", tick.x, -strip)
		line:SetSize(1, axisTop - strip)
		line:SetColorTexture(1, 1, 1, tick.minor and 0.05 or 0.12)
		if tick.label then
			local text = Acquire(texts)
			text:ClearAllPoints()
			local lx = tick.labelX or tick.x
			local anchorPoint = lx < 20 and "TOPLEFT" or (lx > trackWidth - 20 and "TOPRIGHT" or "TOP")
			text:SetPoint(anchorPoint, track, "TOPLEFT", lx, -(axisTop + 2))
			text:SetText("|cff999999" .. tick.label .. "|r")
		end
	end
	-- Zones cliquables (semaines du mois, jours de la semaine), sous les icônes et les barres.
	for _, zone in ipairs(model.zones) do
		local button = Acquire(zones)
		button.zone = zone
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", track, "TOPLEFT", zone.x, -strip)
		button:SetSize(math.max(zone.w, 1), axisTop + AXIS_H - strip)
		button:SetFrameLevel(track:GetFrameLevel() + 1)
	end
	-- Week-ends (Semaine, Mois) : teinte dorée très légère.
	for _, col in ipairs(model.columns) do
		if col.weekend then
			local tint = Acquire(lines)
			tint:ClearAllPoints()
			tint:SetPoint("TOPLEFT", track, "TOPLEFT", col.x, -strip)
			tint:SetSize(col.w, axisTop - strip)
			tint:SetColorTexture(1, 0.82, 0.2, 0.05)
		end
	end
	-- Séparateurs horizontaux des pistes.
	for i = 0, #rows do
		local line = Acquire(lines)
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -(lanesTop + laneH * i))
		line:SetSize(nameWidth + trackWidth, 1)
		line:SetColorTexture(1, 1, 1, 0.08)
	end

	-- Patchs : trait vert et icône bordée de vert.
	for _, patch in ipairs(model.patches) do
		local line = Acquire(lines)
		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", track, "TOPLEFT", patch.x - 1, -strip)
		line:SetSize(2, axisTop - strip)
		line:SetColorTexture(PATCH_RGB[1], PATCH_RGB[2], PATCH_RGB[3], 0.55)
		local mark = Acquire(marks)
		mark.patch = patch
		mark:ClearAllPoints()
		mark:SetPoint("TOP", track, "TOPLEFT", patch.x, -2)
		mark:SetFrameLevel(track:GetFrameLevel() + 2)
	end

	-- Événements.
	for _, cluster in ipairs(model.clusters) do
		local button = Acquire(markers)
		button.cluster = cluster
		button:ClearAllPoints()
		button:SetPoint("TOP", track, "TOPLEFT", cluster.x, -(strip + 2 + cluster.row * rowH))
		button:SetFrameLevel(track:GetFrameLevel() + 4)
		H.SetEventIcon(button.icon, cluster.main)
		local n = #cluster.items
		button.badge:SetText(n > 1 and n or "")
		if cluster.showLabel then
			button.label:SetText(ShortText(cluster.main) .. (n > 1 and (" +" .. (n - 1)) or ""))
		else
			button.label:SetText("")
		end
	end

	-- Présence, une piste par ligne (« Tous » en tête, dorée, puis les personnages) : nom et temps joué
	-- à gauche ; Mois et Tous : cases de chaleur ; Jour et Semaine : barres de séance à leur heure
	-- (Semaine : fond de chaleur discret et total du jour sous les barres s'il y a la place).
	local cells = Pool("cell", CreateCell)
	local withTotals = state.scale == "semaine" and laneH >= TOTALS_MIN_H
	for i, row in ipairs(rows) do
		local y = lanesTop + laneH * (i - 1)
		local name = Acquire(texts)
		name:ClearAllPoints()
		name:SetPoint("LEFT", area, "TOPLEFT", 0, -(y + laneH / 2))
		name:SetText(row.sum and ("|cffffd200" .. L["Tous"] .. "|r") or H.CharName(row.key))
		local played = Acquire(texts)
		played:ClearAllPoints()
		played:SetPoint("RIGHT", area, "TOPLEFT", nameWidth - 8, -(y + laneH / 2))
		played:SetText("|cff999999" .. H.DurationText(row.total) .. "|r")
		local r, g, b = 1, 0.82, 0.2 -- doré : ligne « Tous », ou classe inconnue
		if not row.sum then
			local entry = P.db and P.db.roster and P.db.roster[row.key]
			local color = entry and entry.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.class]
			if color then
				r, g, b = color.r, color.g, color.b
			end
		end
		local max = row.sum and model.maxSum or model.maxCell
		local label = row.sum and L["Tous"] or H.CharName(row.key)

		-- Cases de chaleur (Mois, Tous), ou fond discret (Semaine).
		if model.heat or state.scale == "semaine" then
			for c, col in ipairs(model.columns) do
				local level = HeatLevel(row.cells[c], max)
				if model.heat or level > 0 then
					local cell = Acquire(cells)
					cell.info = { label = label, column = col, value = row.cells[c] }
					cell:ClearAllPoints()
					cell:SetPoint("TOPLEFT", track, "TOPLEFT", col.x + 1, -(y + 2))
					cell:SetSize(math.max(col.w - 2, 1), math.max(laneH - 4, 2))
					cell:SetFrameLevel(track:GetFrameLevel() + 2)
					if level == 0 then
						cell.fill:SetColorTexture(1, 1, 1, 0.03)
					else
						cell.fill:SetColorTexture(r, g, b, (model.heat and 0.85 or 0.3) * level)
					end
				end
			end
		end

		-- Barres de séance (Jour, Semaine) ; ligne « Tous » : toutes les séances, dorées et estompées.
		if not model.heat then
			local list = row.sum and model.lanes or { row }
			local barH = withTotals and math.max(laneH - 15, 4) or math.max(laneH - 6, 3)
			for _, lane in ipairs(list) do
				for _, bb in ipairs(lane.bars) do
					local bar = Acquire(bars)
					bar.session = bb.session
					bar:ClearAllPoints()
					bar:SetPoint("TOPLEFT", track, "TOPLEFT", bb.x, -(y + 3))
					bar:SetSize(bb.w, barH)
					bar:SetFrameLevel(track:GetFrameLevel() + 3)
					bar.fill:SetColorTexture(r, g, b, row.sum and 0.5 or (bb.session.open and 0.45 or 0.9))
				end
			end
			-- Total de chaque jour, sous les barres.
			if withTotals then
				for c, col in ipairs(model.columns) do
					if (row.cells[c] or 0) > 0 then
						local text = Acquire(texts)
						text:ClearAllPoints()
						text:SetPoint("BOTTOM", track, "TOPLEFT", col.x + col.w / 2, -(y + laneH - 1))
						text:SetText("|cff999999" .. H.DurationText(row.cells[c]) .. "|r")
					end
				end
			end
		end
	end
end

-- Rendu au prochain affichage (regroupe les demandes, ex. pendant un redimensionnement).
local function ScheduleRender()
	if renderPending then
		return
	end
	renderPending = true
	C_Timer.After(0.05, Render)
end

-- CONSTRUCTION ------------------------------------------------------------------------------------

-- Panneau de la frise, posé par Histoire.lua à la place de la liste (même emplacement).
function ns.BuildFrise(parent)
	panel = P.CreatePanel(parent, "")
	panel.header:SetText("")

	local prev = H.MakeButton(panel, "<", 24, function()
		state.anchor = ShiftAnchor(state.scale, state.anchor, -1)
		Render()
	end, L["Période précédente (jour, semaine ou mois selon l'échelle)."])
	prev:SetPoint("TOPLEFT", 8, -7)
	panel.prevButton = prev

	local help = H.MakeButton(panel, "?", 22, function() end, "")
	help:SetPoint("TOPRIGHT", -8, -7)
	help:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:AddLine(L["Importance des événements"])
		GameTooltip:AddLine(ImportanceText(), 1, 1, 1, true)
		H.ShowTooltip()
	end)
	local previous = help
	for i = #SCALES, 1, -1 do
		local scale = SCALES[i]
		local button = H.MakeButton(panel, scale.label, scale.key == "semaine" and 62 or 46, function()
			state.scale = scale.key
			Render()
		end, L["Échelle de la frise : %s. Plus la période est longue, moins on montre de détails (bouton « ? »)."]
			:format(scale.label))
		button.scale = scale.key
		button:SetPoint("RIGHT", previous, "LEFT", i == #SCALES and -8 or -2, 0)
		scaleButtons[#scaleButtons + 1] = button
		previous = button
	end
	local nextBtn = H.MakeButton(panel, ">", 24, function()
		state.anchor = ShiftAnchor(state.scale, state.anchor, 1)
		Render()
	end, L["Période suivante."])
	nextBtn:SetPoint("RIGHT", previous, "LEFT", -8, 0)
	panel.nextButton = nextBtn

	periodText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	periodText:SetPoint("LEFT", prev, "RIGHT", 6, 0)
	periodText:SetPoint("RIGHT", nextBtn, "LEFT", -6, 0)
	periodText:SetWordWrap(false)

	area = CreateFrame("Frame", nil, panel)
	area:SetPoint("TOPLEFT", 10, -TOP_BAR - 4)
	area:SetPoint("BOTTOMRIGHT", -10, 6)
	area:SetClipsChildren(true)
	track = CreateFrame("Frame", nil, area)

	emptyText = area:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	emptyText:SetPoint("CENTER")
	emptyText:SetText(L["Rien sur cette période pour les filtres cochés."])
	emptyText:Hide()

	panel:SetScript("OnSizeChanged", ScheduleRender)
	panel:SetScript("OnShow", ScheduleRender)
	if P.SkinPanel then
		P.SkinPanel(panel)
	end
	return panel
end

-- Redessine la frise (données ou filtres changés), si elle est affichée.
function ns.RefreshFrise()
	ScheduleRender()
end

-- Ouvre la frise sur un jour donné, à l'échelle Jour.
function ns.ShowFriseDay(day)
	state.scale, state.anchor = "jour", day
	ScheduleRender()
end
