-- Polypode Histoire: Histoire — fenêtre du journal (années, mois, jours repliables), bouton, commande

local _, ns = ...
local P = Polypode

-- FENÊTRE « Histoire » (bouton de la barre de titre de Polypode, /poly histoire) : le journal de
-- Journal.lua en arbre Année > Mois > Jour, du plus récent au plus ancien, chaque niveau replié ou
-- déplié d'un clic (par défaut seuls l'année, le mois et le jour en cours sont dépliés ; choix
-- gardés dans PolypodeHistoireDB.open). Dans un jour, les événements du plus récent au plus ancien ; les
-- événements identiques de plusieurs personnages à moins de MERGE_WINDOW secondes d'écart sont
-- réunis en une ligne (« Mordsith, Darà terminent le gouffre... ») dont l'infobulle donne le
-- détail. En-tête : nombre d'événements et taille du journal (orange au-delà de ns.WARN_SIZE,
-- rouge au-delà de ns.ALERT_SIZE) ; boutons « Tout replier » / « Tout déplier » et « Exporter ».
-- Clic droit sur une ligne d'événement : la supprimer du journal, après confirmation.
-- FILTRES (cases à gauche de la barre de titre, PolypodeHistoireDB.filters) : aucune cochée = tout
-- le journal ; sinon seuls les événements des catégories cochées (FILTERS, EventCategory), les
-- jours, mois et années sans événement retenu étant omis.

local MERGE_WINDOW = 300 -- secondes
-- Champ de la durée (secondes) des événements de fin d'instance ; il ne compte pas pour réunir
-- les personnages d'une même ligne.
local DURATION_FIELD = { delve = 7, dng = 6, mplus = 8, boss = 7 }
local INSTANCE_KINDS = { delve = "le gouffre", party = "le donjon", raid = "le raid" }
local MIN_WIDTH, MIN_HEIGHT = 600, 220
-- Filtres de la barre de titre : clé, libellé, description de l'infobulle.
local FILTERS = {
	{ key = "conn", label = "Connexions", tip = "Connexions et déconnexions (avec le temps joué)." },
	{ key = "ach", label = "Hauts faits", tip = "Hauts faits obtenus." },
	{ key = "delve", label = "Gouffres", tip = "Entrées dans un gouffre et gouffres (ou sections) terminés." },
	{ key = "dungeon", label = "Donjons", tip = "Entrées dans un donjon, donjons terminés et clés mythiques+." },
	{ key = "raid", label = "Raids", tip = "Entrées dans un raid et boss de raid vaincus." },
}
local CATEGORY_OF_KIND = { ["in"] = "conn", out = "conn", ach = "ach", delve = "delve", dng = "dungeon",
	mplus = "dungeon", boss = "raid" }
local CATEGORY_OF_ENTRY = { delve = "delve", party = "dungeon", raid = "raid" }
local MONTHS = { "Janvier", "Février", "Mars", "Avril", "Mai", "Juin", "Juillet", "Août", "Septembre",
	"Octobre", "Novembre", "Décembre" }
local WEEKDAYS = { "Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi" }

local frame, listPanel

local function Settings()
	PolypodeHistoireDB = PolypodeHistoireDB or {}
	PolypodeHistoireDB.open = PolypodeHistoireDB.open or {}
	PolypodeHistoireDB.filters = PolypodeHistoireDB.filters or {}
	return PolypodeHistoireDB
end

-- Catégorie de filtre d'un événement (nil : groupes, niveaux, niveau d'objet).
local function EventCategory(event)
	local _, _, kind, fields = ns.Parse(event)
	if kind == "enter" then
		return CATEGORY_OF_ENTRY[fields[6]]
	end
	return CATEGORY_OF_KIND[kind]
end

-- Événements d'un jour retenus par les filtres (la liste elle-même si aucun n'est coché).
local function Filtered(list)
	local filters = Settings().filters
	if not next(filters) then
		return list
	end
	local kept = {}
	for _, event in ipairs(list) do
		local category = EventCategory(event)
		if category and filters[category] then
			kept[#kept + 1] = event
		end
	end
	return kept
end

local function ShowTooltip()
	if P.ShowTooltip then
		P.ShowTooltip()
	else
		GameTooltip:Show()
	end
end

-- Repli : choix gardé (open[clé] = true / false), sinon déplié pour la période en cours.
local function IsOpen(key)
	local open = Settings().open[key]
	if open ~= nil then
		return open
	end
	local today = ns.DayOf(GetServerTime())
	return today:sub(1, #key) == key
end

-- TEXTES ------------------------------------------------------------------------------------------

-- Nom court d'un personnage, à la couleur de sa classe.
local function CharName(key)
	local entry = P.db and P.db.roster and P.db.roster[key]
	local name = P.GetDisplayName and P.GetDisplayName(key) or key
	local color = entry and entry.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.class]
	return color and color:WrapTextInColorCode(name) or name
end

local function DifficultyName(id)
	local name = id and GetDifficultyInfo and GetDifficultyInfo(tonumber(id) or 0)
	return name and name ~= "" and name or nil
end

-- (« GetAchievementInfo and GetAchievementInfo(...) » ne garderait que le premier retour : l'id.)
local function AchievementName(id)
	local name
	if GetAchievementInfo then
		name = select(2, GetAchievementInfo(tonumber(id) or 0))
	end
	return name or ("n° " .. tostring(id))
end

-- Ouvre la fenêtre des hauts faits du jeu sur ce haut fait.
local function OpenAchievement(id)
	id = tonumber(id)
	if not id or (GetAchievementInfo and not GetAchievementInfo(id)) then
		return
	end
	if ShowAchievementFrameForAchievement then
		ShowAchievementFrameForAchievement(id)
	elseif AchievementFrame_LoadUI and AchievementFrame_LoadUI() then
		if not AchievementFrame:IsShown() and AchievementFrame_ToggleAchievementFrame then
			AchievementFrame_ToggleAchievementFrame()
		end
		if AchievementFrame_SelectAchievement then
			AchievementFrame_SelectAchievement(id)
		end
	end
end

-- Durée d'une session : « 2 h 05 », « 42 min », « < 1 min ».
local function DurationText(seconds)
	local minutes = math.floor(seconds / 60)
	if minutes < 1 then
		return "< 1 min"
	elseif minutes < 60 then
		return minutes .. " min"
	end
	return string.format("%d h %02d", math.floor(minutes / 60), minutes % 60)
end

-- Durées des sessions : [événement « out »] = secondes depuis le « in » précédent du même personnage
-- (une déco-reco rapide n'ayant laissé ni « out » ni « in », la session reste d'un seul tenant).
local function SessionDurations(days)
	local sorted = {}
	for day in pairs(days) do
		sorted[#sorted + 1] = day
	end
	table.sort(sorted)
	local durations, lastIn = {}, {}
	for _, day in ipairs(sorted) do
		for _, event in ipairs(days[day]) do
			local time, key, kind = ns.Parse(event)
			if kind == "in" then
				lastIn[key] = time
			elseif kind == "out" then
				if lastIn[key] and time then
					durations[event] = time - lastIn[key]
				end
				lastIn[key] = nil
			end
		end
	end
	return durations
end

local function Quoted(text)
	return "« |cffffd200" .. tostring(text) .. "|r »"
end

-- Texte d'une ligne : noms des personnages puis l'action (verbe au pluriel s'ils sont plusieurs).
local function EventText(line)
	local f = line.fields
	local names = {}
	for _, key in ipairs(line.keys) do
		names[#names + 1] = CharName(key)
	end
	local who = table.concat(names, ", ")
	local plural = #line.keys > 1
	local function verb(one, many)
		return plural and many or one
	end
	local kind = line.kind
	-- Parenthèse finale : précisions non vides, puis la durée (du premier personnage de la ligne).
	local function details(...)
		local parts = {}
		for i = 1, select("#", ...) do
			local part = select(i, ...)
			if part and part ~= "" then
				parts[#parts + 1] = part
			end
		end
		if DURATION_FIELD[kind] and line.durations[1] then
			parts[#parts + 1] = DurationText(line.durations[1])
		end
		return #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""
	end
	if kind == "in" then
		return who .. " " .. verb("se connecte", "se connectent")
	elseif kind == "out" then
		local played = #line.keys == 1 and line.durations[1] and (" (" .. DurationText(line.durations[1]) .. ")") or ""
		return who .. " |cff999999" .. verb("se déconnecte", "se déconnectent") .. played .. "|r"
	elseif kind == "grp" then
		return "|cff40ff40L'équipe " .. Quoted(f[4]) .. " se groupe|r (" .. (f[5] or "?") .. " personnages)"
	elseif kind == "lvl" then
		return who .. " " .. verb("atteint", "atteignent") .. " le |cffffd200niveau " .. (f[4] or "?") .. "|r"
	elseif kind == "ach" then
		return who .. " " .. verb("obtient", "obtiennent") .. " le haut fait " .. Quoted(AchievementName(f[4]))
	elseif kind == "ilvl" then
		local gain = (tonumber(f[4]) or 0) - (tonumber(f[5]) or 0)
		return who .. " " .. verb("passe", "passent") .. " au |cffffd200niveau d'objet " .. (f[4] or "?")
			.. "|r |cff40ff40(+" .. gain .. ")|r"
	elseif kind == "enter" then
		local difficulty = f[6] ~= "delve" and DifficultyName(f[5])
		return who .. " |cff999999" .. verb("entre", "entrent") .. " dans " .. (INSTANCE_KINDS[f[6]] or "l'instance")
			.. "|r " .. Quoted(f[4]) .. (difficulty and (" |cff999999(" .. difficulty .. ")|r") or "")
	elseif kind == "delve" then
		-- Palier « 0 » : inconnu (anciens événements, lus dans les données du groupe à l'entrée).
		local tier = f[5] and f[5] ~= "" and f[5] ~= "0" and ("palier " .. f[5]) or nil
		local section = f[6] and f[6] ~= "" and (" : " .. Quoted(f[6])) or ""
		return who .. " " .. verb("termine", "terminent") .. " le gouffre " .. Quoted(f[4]) .. section .. details(tier)
	elseif kind == "dng" then
		return who .. " " .. verb("termine", "terminent") .. " le donjon " .. Quoted(f[4]) .. details(DifficultyName(f[5]))
	elseif kind == "mplus" then
		local timed = f[6] == "1" and "|cff40ff40dans les temps|r" or "|cffff4040hors temps|r"
		return who .. " " .. verb("termine", "terminent") .. " la clé " .. Quoted(f[4]) .. " |cffffd200+"
			.. (f[5] or "?") .. "|r" .. details(timed)
	elseif kind == "boss" then
		return who .. " " .. verb("vainc", "vainquent") .. " " .. Quoted(f[4]) .. " |cff999999"
			.. details(f[6] or "?", DifficultyName(f[5])) .. "|r"
	end
	return who .. " : " .. kind
end

-- Lignes d'un jour : événements de même type et mêmes champs (durée exceptée) réunis s'ils sont
-- à moins de MERGE_WINDOW secondes d'écart et de personnages différents ; renvoyées du plus récent
-- au plus ancien, comme les jours. durations : temps joué des « out » (SessionDurations).
local function DayLines(list, sessions)
	local lines, open = {}, {}
	for _, event in ipairs(list) do
		local time, key, kind, fields = ns.Parse(event)
		local durationField = DURATION_FIELD[kind]
		local mergeKey = table.concat(fields, "~", 3, durationField and math.min(#fields, durationField - 1) or #fields)
		local duration = sessions[event] or (durationField and tonumber(fields[durationField]))
		local line = open[mergeKey]
		local already = false
		for _, known in ipairs(line and line.keys or {}) do
			already = already or known == key
		end
		if line and not already and kind ~= "grp" and time - line.last <= MERGE_WINDOW then
			line.keys[#line.keys + 1] = key
			line.times[#line.times + 1] = time
			line.events[#line.events + 1] = event
			line.durations[#line.keys] = duration
			line.last = time
		else
			line = { event = true, kind = kind, fields = fields, time = time, last = time, keys = { key },
				times = { time }, events = { event }, durations = { duration } }
			lines[#lines + 1] = line
			open[mergeKey] = line
		end
	end
	local reversed = {}
	for i = #lines, 1, -1 do
		reversed[#reversed + 1] = lines[i]
	end
	return reversed
end

-- LISTE -------------------------------------------------------------------------------------------

-- Lignes de la liste : années, mois, jours (du plus récent au plus ancien), puis les événements
-- des jours dépliés. Chaque en-tête : { header = niveau 1..3, key, label, count }.
local function BuildItems()
	local days, lists = {}, {}
	for day, list in pairs(ns.GetDays()) do
		lists[day] = Filtered(list)
		if #lists[day] > 0 then
			days[#days + 1] = day
		end
	end
	table.sort(days, function(a, b)
		return a > b
	end)
	-- Totaux par année et par mois.
	local totals = {}
	for _, day in ipairs(days) do
		local n = #lists[day]
		totals[day:sub(1, 4)] = (totals[day:sub(1, 4)] or 0) + n
		totals[day:sub(1, 7)] = (totals[day:sub(1, 7)] or 0) + n
	end
	local durations = SessionDurations(ns.GetDays())
	local items = {}
	local year, month
	for _, day in ipairs(days) do
		if day:sub(1, 4) ~= year then
			year, month = day:sub(1, 4), nil
			items[#items + 1] = { header = 1, key = year, label = year, count = totals[year] }
		end
		if IsOpen(year) then
			if day:sub(1, 7) ~= month then
				month = day:sub(1, 7)
				items[#items + 1] = { header = 2, key = month, label = MONTHS[tonumber(day:sub(6, 7))] .. " " .. year,
					count = totals[month] }
			end
			if IsOpen(month) then
				local t = time({ year = tonumber(year), month = tonumber(day:sub(6, 7)), day = tonumber(day:sub(9, 10)),
					hour = 12 })
				local list = lists[day]
				items[#items + 1] = { header = 3, key = day,
					label = WEEKDAYS[tonumber(date("%w", t)) + 1] .. " " .. tonumber(day:sub(9, 10)) .. " "
						.. MONTHS[tonumber(day:sub(6, 7))]:lower(), count = #list }
				if IsOpen(day) then
					for _, line in ipairs(DayLines(list, durations)) do
						items[#items + 1] = line
					end
				end
			end
		end
	end
	return items
end

local INDENT = { [1] = "", [2] = "    ", [3] = "        " }

local function FormatItem(item)
	if item.header then
		local mark = IsOpen(item.key) and "-" or "+"
		local color = item.header == 3 and "|cffffffff" or "|cffffd200"
		return INDENT[item.header] .. "|cff999999" .. mark .. "|r " .. color .. item.label .. "|r  |cff999999("
			.. item.count .. ")|r"
	end
	return "            |cff999999" .. date("%H:%M", item.time) .. "|r  " .. EventText(item)
end

local function ItemTooltip(item)
	if item.header then
		return { item.label, item.count .. " événement(s)", IsOpen(item.key) and "Clic : replier" or "Clic : déplier" }
	end
	local lines = { date("%d/%m/%Y", item.time) }
	for i, key in ipairs(item.keys) do
		local played = item.durations[i] and ("  |cff999999(" .. DurationText(item.durations[i]) .. ")|r") or ""
		lines[#lines + 1] = { CharName(key), date("%H:%M:%S", item.times[i]) .. played }
	end
	if item.kind == "ach" then
		lines[#lines + 1] = "Clic : ouvrir le haut fait"
	end
	lines[#lines + 1] = "Clic droit : supprimer"
	return lines
end

-- SUPPRESSION -------------------------------------------------------------------------------------

StaticPopupDialogs["POLYPODE_HISTOIRE_DELETE"] = {
	text = "%s",
	button1 = DELETE or "Supprimer",
	button2 = CANCEL or "Annuler",
	OnAccept = function(_, data)
		ns.Delete(data)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local function AskDelete(item)
	local count = #item.events
	StaticPopup_Show("POLYPODE_HISTOIRE_DELETE", "Supprimer cette entrée du journal ?\n\n"
		.. date("%d/%m/%Y %H:%M", item.time) .. "  " .. EventText(item) .. "\n\n"
		.. (count > 1 and (count .. " événements (un par personnage) seront retirés") or "Elle sera retirée")
		.. ", ici et sur les clients connectés.", nil, item.events)
end

local function OnItemClick(item, mouseButton)
	if item.header then
		Settings().open[item.key] = not IsOpen(item.key)
		ns.Refresh()
	elseif mouseButton == "RightButton" then
		AskDelete(item)
	elseif item.kind == "ach" then
		OpenAchievement(item.fields[4])
	end
end

-- EXPORT ------------------------------------------------------------------------------------------

StaticPopupDialogs["POLYPODE_HISTOIRE_EXPORT"] = {
	text = "%s",
	button1 = "Exporter",
	button2 = CANCEL or "Annuler",
	OnAccept = function()
		local ok, result = ns.Export()
		if ok then
			UIErrorsFrame:AddMessage("Polypode Histoire : " .. result .. " événement(s) archivé(s), écrits à la "
				.. "déconnexion ou au /reload.", 0.25, 1, 0.25)
		else
			UIErrorsFrame:AddMessage("Polypode Histoire : " .. result .. ".", 1, 0.1, 0.1)
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local function AskExport()
	local days, events, cutoff = ns.ExportableDays()
	if days == 0 then
		UIErrorsFrame:AddMessage("Polypode Histoire : rien à exporter (seuls le mois en cours et le précédent sont "
			.. "dans le journal).", 1, 0.82, 0)
		return
	end
	StaticPopup_Show("POLYPODE_HISTOIRE_EXPORT", string.format("Exporter %d jour(s) (%d événements) antérieurs au "
		.. "%s vers l'archive (Polypode Histoire Archive) ?\n\nL'archive est complétée, jamais remplacée ; ces "
		.. "jours sont ensuite retirés du journal, ici et sur les clients connectés.", days, events,
		date("%d/%m/%Y", time({ year = tonumber(cutoff:sub(1, 4)), month = tonumber(cutoff:sub(6, 7)), day = 1, hour = 12 }))))
end

-- FENÊTRE -----------------------------------------------------------------------------------------

local function HeaderText()
	local size, count = ns.GetSize()
	local color = size >= ns.ALERT_SIZE and "|cffff4040" or (size >= ns.WARN_SIZE and "|cffff8000" or "|cff999999")
	local text = "Journal commun  " .. color .. "· " .. count .. " événements · " .. math.ceil(size / 1024) .. " Ko"
	if size >= ns.WARN_SIZE then
		text = text .. " · export conseillé"
	end
	return text .. "|r"
end

local function MakeButton(parent, text, width, onClick, tip)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width, 18)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self:GetText())
		GameTooltip:AddLine(type(tip) == "function" and tip(self) or tip, 1, 1, 1, true)
		ShowTooltip()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	if P.SkinButton then
		P.SkinButton(button)
	end
	return button
end

local function Build()
	local settings = Settings()
	frame = CreateFrame("Frame", "PolypodeHistoireFrame", UIParent, "BackdropTemplate")
	frame:SetSize(math.max(settings.width or 620, MIN_WIDTH), math.max(settings.height or 420, MIN_HEIGHT))
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:SetResizable(true)
	if frame.SetResizeBounds then
		frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT)
	end
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetBackdrop({
		bgFile = "Interface/Tooltips/UI-Tooltip-Background",
		edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0, 0, 0, 0.9)
	frame:Hide()
	tinsert(UISpecialFrames, "PolypodeHistoireFrame") -- Échap ferme la fenêtre

	local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", -4, -4)
	frame.CloseButton = closeBtn

	-- Filtres : cases à gauche de la barre de titre ; le titre, à droite, contre la croix.
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
	title:SetText("Histoire")
	frame.TitleText = title
	frame.filterChecks = {}
	local previous
	for _, filter in ipairs(FILTERS) do
		local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
		check:SetSize(22, 22)
		if previous then
			check:SetPoint("LEFT", previous, "RIGHT", 8, 0)
		else
			check:SetPoint("TOPLEFT", 10, -8)
		end
		check:SetChecked(settings.filters[filter.key] == true)
		check:SetScript("OnClick", function(self)
			Settings().filters[filter.key] = self:GetChecked() and true or nil
			ns.Refresh()
		end)
		check:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:AddLine(filter.label)
			GameTooltip:AddLine(filter.tip, 1, 1, 1, true)
			GameTooltip:AddLine("Cochée : n'affiche que ces événements (avec les autres cases cochées). Aucune "
				.. "case cochée : tout le journal.", 0.7, 0.7, 0.7, true)
			ShowTooltip()
		end)
		check:SetScript("OnLeave", GameTooltip_Hide)
		if P.SkinCheckBox then
			P.SkinCheckBox(check)
		end
		-- Libellé posé après le skin (EllesmereUI le collait à son cadre).
		local text = check.Text or check.text
		if text then
			text:SetText(filter.label)
			text:SetFontObject("GameFontHighlightSmall")
			text:ClearAllPoints()
			text:SetPoint("LEFT", check, "RIGHT", 3, 0)
			check:SetHitRectInsets(0, -(text:GetStringWidth() + 3), 0, 0)
			previous = text
		else
			previous = check
		end
		frame.filterChecks[#frame.filterChecks + 1] = check
	end

	listPanel = P.CreatePanel(frame, "")
	listPanel:SetPoint("TOPLEFT", 12, -36)
	listPanel:SetPoint("BOTTOMRIGHT", -12, 12)
	P.CreateScrollList(listPanel, FormatItem, nil, { onClick = OnItemClick, tooltip = ItemTooltip })

	-- Boutons à droite de l'en-tête du panneau : « Exporter », puis « Tout replier / déplier ».
	local exportBtn = MakeButton(listPanel, "Exporter", 70, AskExport, function()
		local days, events = ns.ExportableDays()
		return "Archive les mois antérieurs au mois précédent (" .. days .. " jour(s), " .. events .. " événements) "
			.. "dans Polypode Histoire Archive, puis les retire du journal pour l'alléger. L'archive est complétée à "
			.. "chaque export, jamais remplacée."
	end)
	exportBtn:SetPoint("TOPRIGHT", -6, -4)
	local collapseBtn = MakeButton(listPanel, "Tout replier", 96, function(self)
		local open = Settings().open
		for _, item in ipairs(frame.items or {}) do
			if item.header then
				open[item.key] = not self.collapseAll
			end
		end
		if not self.collapseAll then
			-- Tout déplier : aussi les mois et jours des années repliées (pas encore listés).
			for day in pairs(ns.GetDays()) do
				open[day:sub(1, 4)], open[day:sub(1, 7)], open[day] = true, true, true
			end
		end
		ns.Refresh()
	end, function(self)
		return self.collapseAll and "Replie toutes les années, mois et jours affichés."
			or "Déplie toutes les années, tous les mois et tous les jours."
	end)
	collapseBtn:SetPoint("RIGHT", exportBtn, "LEFT", -4, 0)
	frame.collapseButton = collapseBtn
	listPanel.header:ClearAllPoints()
	listPanel.header:SetPoint("TOPLEFT", 10, -8)
	listPanel.header:SetPoint("RIGHT", collapseBtn, "LEFT", -6, 0)

	-- Poignée de redimensionnement (taille gardée).
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -4, 4)
	grip:SetFrameLevel(frame:GetFrameLevel() + 10)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function()
		frame:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		Settings().width, Settings().height = frame:GetSize()
	end)

	P.ui.histoireFrame = frame
	if P.SkinFrame then
		P.SkinFrame(frame)
	end
	if P.SkinPanel then
		P.SkinPanel(listPanel)
	end
end

-- Remplit la liste, si la fenêtre est ouverte.
function ns.Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	local items = BuildItems()
	frame.items = items
	local anyOpen = false
	for _, item in ipairs(items) do
		anyOpen = anyOpen or (item.header and IsOpen(item.key))
	end
	frame.collapseButton.collapseAll = anyOpen
	frame.collapseButton:SetText(anyOpen and "Tout replier" or "Tout déplier")
	listPanel.header:SetText(HeaderText())
	listPanel.emptyText:SetText(next(Settings().filters) and "Aucun événement pour les filtres cochés."
		or "Aucun événement noté pour l'instant.")
	P.SetListData(listPanel, items)
end
P.RefreshHistoire = ns.Refresh

-- Ouvre / ferme la fenêtre (bouton « Histoire », /poly histoire).
function P.ToggleHistoire()
	if not frame then
		Build()
	end
	if frame:IsShown() then
		frame:Hide()
	else
		frame:Show()
		ns.Refresh()
	end
end

-- INTÉGRATION À POLYPODE --------------------------------------------------------------------------

if P.AddTitleButton then
	P.AddTitleButton({
		text = "Histoire",
		width = 70,
		onClick = function()
			P.ToggleHistoire()
		end,
		tooltip = { "Polypode Histoire", "Journal commun de tous les personnages joués : connexions, groupes "
			.. "d'équipe, gouffres, donjons, clés M+, boss de raid, hauts faits, niveaux, niveau d'objet." },
		onCreate = function(button)
			P.ui.histoireButton = button
		end,
	})
end

if P.RegisterSlashCommand then
	P.RegisterSlashCommand("histoire", P.ToggleHistoire, "journal commun des personnages (Polypode Histoire)")
end
