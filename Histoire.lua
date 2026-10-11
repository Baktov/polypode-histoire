-- Polypode Histoire: Histoire — fenêtre du journal (années, mois, jours repliables), bouton, commande

local _, ns = ...
local P = Polypode

-- FENÊTRE « Histoire » (bouton de la barre de titre de Polypode, /poly histoire) : le journal de
-- Journal.lua en arbre Année > Mois > Jour, du plus récent au plus ancien, chaque niveau replié ou
-- déplié d'un clic (par défaut seuls l'année, le mois et le jour en cours sont dépliés ; choix
-- gardés dans PolypodeHistoireDB.open). Dans un jour, les événements dans l'ordre de l'heure ; les
-- événements identiques de plusieurs personnages à moins de MERGE_WINDOW secondes d'écart sont
-- réunis en une ligne (« Mordsith, Darà terminent le gouffre... ») dont l'infobulle donne le
-- détail. En-tête : nombre d'événements et taille du journal (orange au-delà de ns.WARN_SIZE,
-- rouge au-delà de ns.ALERT_SIZE) ; boutons « Tout replier » / « Tout déplier » et « Exporter ».

local MERGE_WINDOW = 300 -- secondes
local MIN_WIDTH, MIN_HEIGHT = 420, 220
local MONTHS = { "Janvier", "Février", "Mars", "Avril", "Mai", "Juin", "Juillet", "Août", "Septembre",
	"Octobre", "Novembre", "Décembre" }
local WEEKDAYS = { "Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi" }

local frame, listPanel

local function Settings()
	PolypodeHistoireDB = PolypodeHistoireDB or {}
	PolypodeHistoireDB.open = PolypodeHistoireDB.open or {}
	return PolypodeHistoireDB
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

local function AchievementName(id)
	local _, name = GetAchievementInfo and GetAchievementInfo(tonumber(id) or 0)
	return name or ("n° " .. tostring(id))
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
	if kind == "in" then
		return who .. " " .. verb("se connecte", "se connectent")
	elseif kind == "out" then
		return who .. " |cff999999" .. verb("se déconnecte", "se déconnectent") .. "|r"
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
	elseif kind == "delve" then
		local tier = f[5] and f[5] ~= "" and (" (palier " .. f[5] .. ")") or ""
		return who .. " " .. verb("termine", "terminent") .. " le gouffre " .. Quoted(f[4]) .. tier
	elseif kind == "dng" then
		local difficulty = DifficultyName(f[5])
		return who .. " " .. verb("termine", "terminent") .. " le donjon " .. Quoted(f[4])
			.. (difficulty and (" (" .. difficulty .. ")") or "")
	elseif kind == "mplus" then
		local timed = f[6] == "1" and "|cff40ff40dans les temps|r" or "|cffff4040hors temps|r"
		return who .. " " .. verb("termine", "terminent") .. " la clé " .. Quoted(f[4]) .. " |cffffd200+"
			.. (f[5] or "?") .. "|r (" .. timed .. ")"
	elseif kind == "boss" then
		local difficulty = DifficultyName(f[5])
		return who .. " " .. verb("vainc", "vainquent") .. " " .. Quoted(f[4]) .. " |cff999999(" .. (f[6] or "?")
			.. (difficulty and (", " .. difficulty) or "") .. ")|r"
	end
	return who .. " : " .. kind
end

-- Lignes d'un jour : événements dans l'ordre, ceux de même type et mêmes champs réunis s'ils sont
-- à moins de MERGE_WINDOW secondes d'écart et de personnages différents.
local function DayLines(list)
	local lines, open = {}, {}
	for _, event in ipairs(list) do
		local time, key, kind, fields = ns.Parse(event)
		local mergeKey = table.concat(fields, "~", 3)
		local line = open[mergeKey]
		local already = false
		for _, known in ipairs(line and line.keys or {}) do
			already = already or known == key
		end
		if line and not already and kind ~= "grp" and time - line.last <= MERGE_WINDOW then
			line.keys[#line.keys + 1] = key
			line.times[#line.times + 1] = time
			line.last = time
		else
			line = { event = true, kind = kind, fields = fields, time = time, last = time, keys = { key },
				times = { time } }
			lines[#lines + 1] = line
			open[mergeKey] = line
		end
	end
	return lines
end

-- LISTE -------------------------------------------------------------------------------------------

-- Lignes de la liste : années, mois, jours (du plus récent au plus ancien), puis les événements
-- des jours dépliés. Chaque en-tête : { header = niveau 1..3, key, label, count }.
local function BuildItems()
	local days = {}
	for day, list in pairs(ns.GetDays()) do
		if #list > 0 then
			days[#days + 1] = day
		end
	end
	table.sort(days, function(a, b)
		return a > b
	end)
	-- Totaux par année et par mois.
	local totals = {}
	for _, day in ipairs(days) do
		local n = #ns.GetDays()[day]
		totals[day:sub(1, 4)] = (totals[day:sub(1, 4)] or 0) + n
		totals[day:sub(1, 7)] = (totals[day:sub(1, 7)] or 0) + n
	end
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
				local list = ns.GetDays()[day]
				items[#items + 1] = { header = 3, key = day,
					label = WEEKDAYS[tonumber(date("%w", t)) + 1] .. " " .. tonumber(day:sub(9, 10)) .. " "
						.. MONTHS[tonumber(day:sub(6, 7))]:lower(), count = #list }
				if IsOpen(day) then
					for _, line in ipairs(DayLines(list)) do
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
		lines[#lines + 1] = { CharName(key), date("%H:%M:%S", item.times[i]) }
	end
	return lines
end

local function OnItemClick(item)
	if item.header then
		Settings().open[item.key] = not IsOpen(item.key)
		ns.Refresh()
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
	frame:SetSize(settings.width or 560, settings.height or 420)
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

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -14)
	title:SetText("Histoire")
	frame.TitleText = title

	local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", -4, -4)
	frame.CloseButton = closeBtn

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
	listPanel.emptyText:SetText("Aucun événement noté pour l'instant.")
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
