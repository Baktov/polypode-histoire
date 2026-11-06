-- Polypode Histoire: Liste — vue « Liste » du journal, à la manière du site Histoire v2
--
-- Liste défilante propre à Histoire (ScrollBox du jeu, lignes de hauteurs différentes, recyclées) :
-- un fil vertical bronze à gauche relie les jours d'un mois ; chaque jour s'ouvre sur son grand
-- numéro doré posé sur le fil, puis la date, le nombre d'événements, le temps joué et le patch du
-- jour ; ses événements suivent, avec l'heure, l'icône du type et le texte (connexions : un point
-- sur le fil). Années et mois restent des titres repliables. Clics (repli, haut fait, clic droit :
-- supprimer) et infobulles : fonctions de Histoire.lua (handlers). Chargé après Histoire.lua.

local _, ns = ...
local P = Polypode

local GUTTER = 48 -- largeur de la marge du fil (numéros des jours)
local THREAD_X = 22 -- position du fil dans la marge
local TIME_W = 36
local ICON = 16
local HEIGHT = { [1] = 30, [2] = 26, [3] = 38 }
local EVENT_H = 22
local FONT = "Fonts\\FRIZQT__.TTF" -- police du jeu, présente dans tous les clients
local GOLD = { 1, 0.82, 0.2 }
local THREAD_RGB = { 0.62, 0.47, 0.25 }

-- Hauteur d'une ligne selon son genre (titre d'année, de mois, jour, événement).
local function Extent(_, item)
	return item.header and HEIGHT[item.header] or EVENT_H
end

-- Éléments d'une ligne, créés une fois (lignes recyclées : Apply les montre ou les cache).
local function Setup(row, handlers)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local hover = row:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.06)

	local function Thread(layer)
		local t = row:CreateTexture(nil, layer or "BACKGROUND")
		t:SetColorTexture(THREAD_RGB[1], THREAD_RGB[2], THREAD_RGB[3], 0.75)
		t:SetWidth(1)
		return t
	end
	row.thread = Thread() -- ligne d'événement : toute la hauteur
	row.thread:SetPoint("TOP", row, "TOPLEFT", THREAD_X, 0)
	row.thread:SetPoint("BOTTOM", row, "BOTTOMLEFT", THREAD_X, 0)
	row.threadTop = Thread() -- jour : au-dessus et au-dessous du numéro
	row.threadTop:SetPoint("TOP", row, "TOPLEFT", THREAD_X, 0)
	row.threadTop:SetHeight(5)
	row.threadBottom = Thread()
	row.threadBottom:SetPoint("BOTTOM", row, "BOTTOMLEFT", THREAD_X, 0)
	row.threadBottom:SetHeight(5)

	row.rule = row:CreateTexture(nil, "BACKGROUND") -- filet des titres et du haut des jours
	row.rule:SetHeight(1)

	row.num = row:CreateFontString(nil, "OVERLAY")
	row.num:SetFont(FONT, 22, "")
	row.num:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	row.num:SetPoint("CENTER", row, "LEFT", THREAD_X, 0)

	row.mark = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.title:SetWordWrap(false)
	row.title:SetJustifyH("LEFT")
	row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.right:SetPoint("RIGHT", -6, 0)
	row.right:SetJustifyH("RIGHT")

	row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.time:SetPoint("LEFT", GUTTER, 0)
	row.time:SetWidth(TIME_W)
	row.time:SetJustifyH("LEFT")
	row.iconBorder = row:CreateTexture(nil, "ARTWORK")
	row.iconBorder:SetSize(ICON + 2, ICON + 2)
	row.iconBorder:SetPoint("LEFT", GUTTER + TIME_W, 0)
	row.iconBorder:SetColorTexture(0, 0, 0, 0.9)
	row.icon = row:CreateTexture(nil, "OVERLAY")
	row.icon:SetSize(ICON, ICON)
	row.icon:SetPoint("CENTER", row.iconBorder)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.dot = row:CreateTexture(nil, "ARTWORK")
	row.dot:SetSize(5, 5)
	row.dot:SetPoint("CENTER", row.iconBorder)
	row.dot:SetColorTexture(0.6, 0.6, 0.6, 0.8)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.text:SetPoint("LEFT", row.iconBorder, "RIGHT", 6, 0)
	row.text:SetPoint("RIGHT", -6, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)

	row:SetScript("OnEnter", function(self)
		local lines = self.item and handlers.tooltip(self.item)
		if not lines or #lines == 0 then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		for i, line in ipairs(lines) do
			if type(line) == "table" then
				GameTooltip:AddDoubleLine(line[1] or "", line[2] or "", 1, 1, 1, 1, 1, 1)
			elseif i == 1 then
				GameTooltip:AddLine(line)
			else
				GameTooltip:AddLine(line, 1, 1, 1)
			end
		end
		handlers.showTooltip()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnClick", function(self, mouseButton)
		if self.item then
			handlers.onClick(self.item, mouseButton)
		end
	end)
	row.ready = true
end

local function Apply(row, item, handlers)
	row.item = item
	local header = item.header
	local isDay, isEvent = header == 3, not header
	row.thread:SetShown(isEvent)
	row.threadTop:SetShown(isDay)
	row.threadBottom:SetShown(isDay)
	row.num:SetShown(isDay)
	row.mark:SetShown(header ~= nil)
	row.title:SetShown(header ~= nil)
	row.right:SetShown(header ~= nil)
	row.time:SetShown(isEvent)
	row.text:SetShown(isEvent)
	row.rule:SetShown(header ~= nil)

	if header then
		local mark = item.count > 0 and (handlers.isOpen(item.key) and "-" or "+") or ""
		row.mark:SetText(mark)
		row.mark:ClearAllPoints()
		row.title:ClearAllPoints()
		row.rule:ClearAllPoints()
		if isDay then
			row.num:SetText(tonumber(item.key:sub(9, 10)))
			row.mark:SetPoint("LEFT", GUTTER, 0)
			row.title:SetPoint("LEFT", GUTTER + 12, 0)
			row.title:SetFontObject("GameFontHighlight")
			row.rule:SetPoint("TOPLEFT", GUTTER, 0)
			row.rule:SetPoint("TOPRIGHT", 0, 0)
			row.rule:SetColorTexture(THREAD_RGB[1], THREAD_RGB[2], THREAD_RGB[3], 0.35)
			local title = item.label
			if item.patch then
				title = title .. "  " .. handlers.patchText(item)
			end
			row.title:SetText(title)
			local parts = {}
			if item.count > 0 then
				parts[#parts + 1] = handlers.countText(item.count)
			end
			if (item.played or 0) > 0 then
				parts[#parts + 1] = handlers.playedText(item.played)
			end
			row.right:SetText("|cff999999" .. table.concat(parts, "  ·  ") .. "|r")
		else
			row.mark:SetPoint("LEFT", 6, 0)
			row.title:SetPoint("LEFT", 18, 0)
			row.title:SetFontObject(header == 1 and "GameFontNormalLarge" or "GameFontNormal")
			row.title:SetText(item.label)
			row.rule:SetPoint("BOTTOMLEFT", 4, 2)
			row.rule:SetPoint("BOTTOMRIGHT", -4, 2)
			row.rule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], header == 1 and 0.45 or 0.2)
			row.right:SetText(item.count > 0 and ("|cff999999" .. handlers.countText(item.count) .. "|r") or "")
		end
		row.title:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
		row.icon:Hide()
		row.iconBorder:Hide()
		row.dot:Hide()
		return
	end

	-- Événement : heure, icône du type (connexions : point sur le fil), texte.
	row.time:SetText("|cff999999" .. date("%H:%M", item.time) .. "|r")
	local quiet = item.kind == "in" or item.kind == "out"
	row.dot:SetShown(quiet)
	row.icon:SetShown(not quiet)
	row.iconBorder:SetShown(not quiet)
	if not quiet then
		handlers.setIcon(row.icon, item)
	end
	row.text:SetFontObject(quiet and "GameFontHighlightSmall" or "GameFontHighlight")
	row.text:SetText(handlers.eventText(item))
end

-- Construit la liste dans panel, sous top px. handlers : onClick(item, bouton), tooltip(item),
-- showTooltip(), isOpen(clé), eventText(item), setIcon(texture, item), countText(n),
-- playedText(secondes), patchText(item). Renvoie { SetItems(items), ScrollToKey(clé) }.
function ns.BuildList(panel, handlers, top)
	local inset = 6
	local scrollBox = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
	local scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtentCalculator(Extent)
	view:SetElementInitializer("Button", function(row, item)
		if not row.ready then
			Setup(row, handlers)
		end
		Apply(row, item, handlers)
		if GameTooltip:IsOwned(row) then
			row:GetScript("OnEnter")(row) -- liste reconstruite sous le curseur : infobulle à jour
		end
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
	local topLeft = CreateAnchor("TOPLEFT", panel, "TOPLEFT", inset, -top)
	ScrollUtil.AddManagedScrollBarVisibilityBehavior(scrollBox, scrollBar,
		{ topLeft, CreateAnchor("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 6) },
		{ topLeft, CreateAnchor("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -inset, 6) })
	if P.SkinScrollBar then
		P.SkinScrollBar(scrollBar)
	end

	local emptyText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	emptyText:SetPoint("TOPLEFT", inset + 6, -top - 6)
	emptyText:SetPoint("RIGHT", -inset, 0)
	emptyText:SetJustifyH("LEFT")

	local list = { emptyText = emptyText }
	local pendingKey
	function list.SetItems(items)
		scrollBox:SetDataProvider(CreateDataProvider(items), ScrollBoxConstants.RetainScrollPosition)
		emptyText:SetShown(#items == 0)
		if pendingKey then
			for index, item in ipairs(items) do
				if item.header == 3 and item.key == pendingKey then
					scrollBox:ScrollToElementDataIndex(index, ScrollBoxConstants.AlignBegin)
					break
				end
			end
			pendingKey = nil
		end
	end
	-- Jour à amener en haut de la liste au prochain remplissage (clic sur une icône de la frise).
	function list.ScrollToKey(key)
		pendingKey = key
	end
	return list
end
