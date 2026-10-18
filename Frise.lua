-- Polypode Histoire: Frise — vue chronologique horizontale du journal (jour, semaine, mois, tous)

local _, ns = ...
local P = Polypode

-- VUE « Frise » de la fenêtre Histoire (boutons Liste / Frise en haut à gauche) : axe horizontal
-- sur une période (Jour : cadré sur la plage jouée ; Semaine : du lundi au dimanche ; Mois ; Tous :
-- tout le journal), piste des événements (icône, texte court, infobulle détaillée, clic : le jour
-- dans la liste) et une piste de sessions par personnage (couleur de classe). Mêmes règles que le
-- site Histoire (src/timeline.js) : plus la période est longue, moins on montre de détails (poids
-- WEIGHT, seuil MIN_WEIGHT) ; une catégorie cochée en bas de la fenêtre montre tous ses
-- événements ; événements voisins à moins de CLUSTER_PX regroupés (compteur, icône et texte du
-- plus marquant). La frise suit la largeur de la fenêtre (regroupement refait au redimensionnement).
-- Journées : celles du journal (minuit, ns.DayOf). Éléments graphiques recyclés (pools).

local H = ns.H -- outils de Histoire.lua (chargé avant ce fichier)

local SCALES = {
	{ key = "jour", label = "Jour" },
	{ key = "semaine", label = "Semaine" },
	{ key = "mois", label = "Mois" },
	{ key = "tous", label = "Tous" },
}
local WEIGHT = {
	boss = 3, mplus = 3, lvl = 3, mount = 3,
	ach = 2, dng = 2, renown = 2, guild = 2,
	delve = 1, toy = 1, pet = 1, rep = 1, ilvl = 1, friend = 1, club = 1, grp = 1,
	enter = 0,
}
local MIN_WEIGHT = { jour = 0, semaine = 1, mois = 2, tous = 3 }
local KIND_LABELS = {
	boss = "boss de raid vaincu", mplus = "clé mythique+ terminée", lvl = "niveau atteint", mount = "monture obtenue",
	ach = "haut fait", dng = "donjon terminé", renown = "palier de renom", guild = "guilde rejointe ou quittée",
	delve = "gouffre (ou section) terminé", toy = "jouet", pet = "mascotte", rep = "rang de réputation",
	ilvl = "niveau d'objet", friend = "ami ajouté ou retiré", club = "communauté rejointe ou quittée",
	grp = "équipe groupée", enter = "entrée dans une instance",
}
-- Icônes du jeu par type (mêmes que le site ; absentes de WoW Forever : point d'interrogation).
local ICONS = {
	ach = "achievement_general", delve = "ui_delves", dng = "achievement_dungeon_gloryofthehero",
	mplus = "achievement_challengemode_gold", boss = "achievement_boss_ragnaros", toy = "inv_misc_toy_10",
	mount = "ability_mount_ridinghorse", pet = "inv_box_petcarrier_01", renown = "achievement_reputation_08",
	rep = "achievement_reputation_01", friend = "achievement_guildperk_everybodysfriend",
	guild = "inv_shirt_guildtabard_01", club = "inv_misc_groupneedmore", grp = "inv_misc_groupneedmore",
	lvl = "achievement_level_80", ilvl = "inv_sword_04", enter = "spell_arcane_portaldalaran",
}
local PATCH_ICON = "inv_scroll_03"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local CLUSTER_PX = 30 -- en dessous : événements voisins regroupés
local LABEL_PX = 100 -- voisins de la même rangée au moins à cette distance : texte court affiché
local TOOLTIP_MAX = 8
local ICON = 22
local LABEL_H = 13
local PATCH_STRIP = 20 -- bande des icônes de patch, au-dessus des événements
local AXIS_H = 14
local TOP_BAR = 30 -- barre du haut (chevrons, échelles)
local JOUR_MARGIN = 1800 -- vue Jour : marge autour de la plage jouée (s)
local JOUR_MIN_SPAN = 3 * 3600
local PATCH_RGB = { 0.25, 1, 0.25 }
local MONTHS_SHORT = { "janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc." }
local WEEKDAYS_SHORT = { "dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam." }

local panel, area, track, periodText, emptyText
local scaleButtons = {}
local state = { scale = "semaine" } -- anchor : jour d'ancrage de la période (nil : dernier jour joué)
local renderPending

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
	local months = H.MONTHS
	if scale == "jour" then
		return H.WEEKDAYS[Weekday(period.startKey) + 1] .. " " .. d .. " " .. months[m]:lower() .. " " .. y
	elseif scale == "mois" then
		return months[m] .. " " .. y
	end
	local ly, lm, ld = DayParts(AddDays(period.endKey, -1))
	if scale == "semaine" then
		return "Semaine du " .. d .. (m ~= lm and (" " .. months[m]:lower()) or "") .. " au " .. ld .. " "
			.. months[lm]:lower() .. " " .. ly
	end
	return "Du " .. d .. " " .. months[m]:lower() .. " " .. y .. " au " .. ld .. " " .. months[lm]:lower() .. " " .. ly
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

-- Texte court sous l'icône (f[4] : premier champ après heure~clé~type).
local function ShortText(line)
	local f, n = line.fields, #line.keys > 1 and (" ×" .. #line.keys) or ""
	local kind = line.kind
	if kind == "lvl" then
		return "Niv. " .. (f[4] or "?")
	elseif kind == "ilvl" then
		return "iLvl " .. (f[4] or "?")
	elseif kind == "ach" then
		return "Haut fait" .. n
	elseif kind == "boss" or kind == "dng" or kind == "enter" then
		return f[4] or "?"
	elseif kind == "mplus" then
		return "+" .. (f[5] or "?") .. " " .. (f[4] or "")
	elseif kind == "delve" then
		return "Gouffre" .. ((f[5] and f[5] ~= "" and f[5] ~= "0") and (" " .. f[5]) or "")
	elseif kind == "renown" then
		return "Renom " .. (f[5] or "?")
	elseif kind == "rep" then
		return f[5] or "Réputation"
	elseif kind == "toy" or kind == "mount" or kind == "pet" then
		return (f[5] and f[5] ~= "") and f[5] or "?"
	elseif kind == "friend" or kind == "guild" or kind == "club" then
		return (f[5] == "+" and "+ " or "- ") .. (f[4] or "?")
	elseif kind == "grp" then
		return "Équipe " .. (f[4] or "?")
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
	for _, s in ipairs(Intervals(days)) do
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
			ticks[#ticks + 1] = { x = x(t), label = hour % every == 0 and (hour .. " h") or nil, minor = hour % every ~= 0 }
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

	local patches = {}
	if H.IS_RETAIL and settings.showPatches then
		for day, name in pairs(H.PATCHES) do
			if day >= period.startKey and day < period.endKey then
				patches[#patches + 1] = { day = day, name = name, x = x(DayStart(day)) }
			end
		end
	end

	return { period = period, clusters = clusters, lanes = lanes, ticks = ticks, patches = patches, count = #items }
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

local function SetIcon(texture, name)
	if not (name and texture:SetTexture("Interface\\Icons\\" .. name)) then
		texture:SetTexture(FALLBACK_ICON)
	end
end

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
	GameTooltip:AddLine(n > 1 and (n .. " événements") or KIND_LABELS[cluster.main.kind] or cluster.main.kind)
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
		GameTooltip:AddLine("... et " .. (n - TOOLTIP_MAX) .. " autre(s)", 0.6, 0.6, 0.6)
	end
	GameTooltip:AddLine("Clic : voir ce jour dans la liste", 0.7, 0.7, 0.7)
	H.ShowTooltip()
end

local function BarTooltip(self)
	local s = self.session
	if not s then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:AddLine(H.CharName(s.key))
	GameTooltip:AddLine(date("%d/%m ", s.start) .. TimeLabel(s.start) .. " → " .. TimeLabel(s.stop)
		.. (s.open and " (fin non notée)" or "") .. " · " .. H.DurationText(s.stop - s.start), 1, 1, 1)
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
	local lines = { "|cff40ff40Un filtre coché prend la main :|r une catégorie cochée en bas de la fenêtre montre "
		.. "tous ses événements, quelle que soit l'échelle.", "", "|cffffd200Poids des événements|r" }
	for _, w in ipairs(weights) do
		table.sort(byWeight[w])
		lines[#lines + 1] = "|cffffd200" .. w .. "|r : " .. table.concat(byWeight[w], ", ")
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "|cffffd200Seuil par échelle|r"
	for _, scale in ipairs(SCALES) do
		lines[#lines + 1] = scale.label .. " : poids " .. MIN_WEIGHT[scale.key] .. " et plus"
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "Connexions : montrées par les barres de session. Événements trop proches : regroupés "
		.. "(compteur), icône et texte du plus marquant."
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
	return bar
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

	-- Colonne des noms : largeur du nom le plus long (nom et temps joué sur une ligne).
	local probe = Acquire(texts)
	local width = area:GetWidth()
	local model = BuildModel(math.max(width - 160, 50)) -- première passe : noms à mesurer
	local nameWidth = 70
	for _, lane in ipairs(model.lanes) do
		probe:SetText(H.CharName(lane.key) .. "  " .. H.DurationText(lane.total))
		nameWidth = math.max(nameWidth, probe:GetStringWidth() + 12)
	end
	probe:Hide()
	local trackWidth = math.max(width - nameWidth - 8, 50)
	model = BuildModel(trackWidth)

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

	-- Hauteurs : bande des patchs, deux rangées d'événements, pistes, axe.
	local height = area:GetHeight()
	local strip = #model.patches > 0 and PATCH_STRIP or 0
	local rowH = ICON + LABEL_H + 4
	local eventsH = strip + 2 * rowH + 4
	local laneCount = math.max(#model.lanes, 1)
	local laneH = math.max(8, math.min(18, math.floor((height - eventsH - AXIS_H) / laneCount)))
	local lanesTop = eventsH
	local axisTop = lanesTop + laneH * #model.lanes

	-- Libellé de la piste des événements.
	local evLabel = Acquire(texts)
	evLabel:ClearAllPoints()
	evLabel:SetPoint("LEFT", area, "TOPLEFT", 0, -(strip + rowH))
	evLabel:SetText("|cff999999Événements|r")

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
	-- Séparateurs horizontaux des pistes.
	for i = 0, #model.lanes do
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
	end

	-- Événements.
	for _, cluster in ipairs(model.clusters) do
		local button = Acquire(markers)
		button.cluster = cluster
		button:ClearAllPoints()
		button:SetPoint("TOP", track, "TOPLEFT", cluster.x, -(strip + 2 + cluster.row * rowH))
		button:SetFrameLevel(track:GetFrameLevel() + 3)
		SetIcon(button.icon, ICONS[cluster.main.kind])
		local n = #cluster.items
		button.badge:SetText(n > 1 and n or "")
		if cluster.showLabel then
			button.label:SetText(ShortText(cluster.main) .. (n > 1 and (" +" .. (n - 1)) or ""))
		else
			button.label:SetText("")
		end
	end

	-- Sessions : nom et temps joué à gauche, barres à la couleur de classe.
	for i, lane in ipairs(model.lanes) do
		local y = lanesTop + laneH * (i - 1)
		local name = Acquire(texts)
		name:ClearAllPoints()
		name:SetPoint("LEFT", area, "TOPLEFT", 0, -(y + laneH / 2))
		name:SetText(H.CharName(lane.key))
		local played = Acquire(texts)
		played:ClearAllPoints()
		played:SetPoint("RIGHT", area, "TOPLEFT", nameWidth - 8, -(y + laneH / 2))
		played:SetText("|cff999999" .. H.DurationText(lane.total) .. "|r")
		local entry = P.db and P.db.roster and P.db.roster[lane.key]
		local color = entry and entry.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.class]
		for _, b in ipairs(lane.bars) do
			local bar = Acquire(bars)
			bar.session = b.session
			bar:ClearAllPoints()
			bar:SetPoint("TOPLEFT", track, "TOPLEFT", b.x, -(y + 3))
			bar:SetSize(b.w, math.max(laneH - 6, 3))
			bar.fill:SetColorTexture(color and color.r or 0.9, color and color.g or 0.7, color and color.b or 0.2,
				b.session.open and 0.45 or 0.9)
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
	end, "Période précédente (jour, semaine ou mois selon l'échelle).")
	prev:SetPoint("TOPLEFT", 8, -7)
	panel.prevButton = prev

	local help = H.MakeButton(panel, "?", 22, function() end, "")
	help:SetPoint("TOPRIGHT", -8, -7)
	help:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:AddLine("Importance des événements")
		GameTooltip:AddLine(ImportanceText(), 1, 1, 1, true)
		H.ShowTooltip()
	end)
	local previous = help
	for i = #SCALES, 1, -1 do
		local scale = SCALES[i]
		local button = H.MakeButton(panel, scale.label, scale.key == "semaine" and 62 or 46, function()
			state.scale = scale.key
			Render()
		end, "Échelle de la frise : " .. scale.label:lower() .. ". Plus la période est longue, moins on montre de "
			.. "détails (bouton « ? »).")
		button.scale = scale.key
		button:SetPoint("RIGHT", previous, "LEFT", i == #SCALES and -8 or -2, 0)
		scaleButtons[#scaleButtons + 1] = button
		previous = button
	end
	local nextBtn = H.MakeButton(panel, ">", 24, function()
		state.anchor = ShiftAnchor(state.scale, state.anchor, 1)
		Render()
	end, "Période suivante.")
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
	emptyText:SetText("Rien sur cette période pour les filtres cochés.")
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
