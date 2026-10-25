-- Polypode Histoire: Histoire — fenêtre du journal (années, mois, jours repliables), bouton, commande

local _, ns = ...
local P = Polypode
local L = ns.L

-- FENÊTRE « Histoire » (bouton de la barre de titre de Polypode, /poly histoire) : le journal de
-- Journal.lua en arbre Année > Mois > Jour, du plus récent au plus ancien, chaque niveau replié ou
-- déplié d'un clic (par défaut seuls l'année, le mois et le jour en cours sont dépliés ; choix
-- gardés dans PolypodeHistoireDB.open). Dans un jour, les événements du plus récent au plus ancien ; les
-- événements identiques de plusieurs personnages à moins de MERGE_WINDOW secondes d'écart sont
-- réunis en une ligne (« Mordsith, Darà terminent le gouffre... ») dont l'infobulle donne le
-- détail. En-tête : nombre d'événements et taille du journal (orange au-delà de ns.WARN_SIZE,
-- rouge au-delà de ns.ALERT_SIZE) ; boutons « Tout replier » / « Tout déplier » et « Exporter ».
-- Clic droit sur une ligne d'événement : la supprimer du journal, après confirmation.
-- FILTRES (cases en bas à gauche de la fenêtre, PolypodeHistoireDB.filters) : aucune cochée = tout
-- le journal ; sinon seuls les événements des catégories cochées (FILTERS, EventCategory), les
-- jours, mois et années sans événement retenu étant omis.

local MERGE_WINDOW = 300 -- secondes
-- Champ de la durée (secondes) des événements de fin d'instance ; il ne compte pas pour réunir
-- les personnages d'une même ligne.
local DURATION_FIELD = { delve = 7, dng = 6, mplus = 8, boss = 7 }
local MIN_WIDTH, MIN_HEIGHT = 560, 220
local DEFAULT_WIDTH, DEFAULT_HEIGHT = 620, 420
-- Filtres (bas de la fenêtre) : clé, libellé de l'infobulle, abrégé à droite de la case, description.
local FILTERS = {
	{ key = "conn", label = L["Connexions"], short = L["Con."], tip = L["Connexions et déconnexions (avec le temps joué)."] },
	{ key = "ach", label = L["Hauts faits"], short = L["H-F"], tip = L["Hauts faits obtenus."] },
	{ key = "delve", label = L["Gouffres"], short = L["Gou."], tip = L["Entrées dans un gouffre et gouffres (ou sections) terminés."] },
	{ key = "dungeon", label = L["Donjons"], short = L["Don."], tip = L["Entrées dans un donjon, donjons terminés et clés mythiques+."] },
	{ key = "raid", label = L["Raids"], short = L["Rai."], tip = L["Entrées dans un raid et boss de raid vaincus."] },
	{ key = "coll", label = L["Collections"], short = L["Col."], tip = L["Jouets, montures et mascottes obtenus."] },
	{ key = "rep", label = L["Renom et réputation"], short = L["Rép."], tip = L["Paliers de renom et rangs de réputation "
		.. "atteints (amitié comprise)."] },
	{ key = "social", label = L["Social"], short = L["Soc."], tip = L["Amis (du personnage ou Battle.net) ajoutés ou "
		.. "retirés, guildes et communautés rejointes ou quittées."] },
}
local CATEGORY_OF_KIND = { ["in"] = "conn", out = "conn", ach = "ach", delve = "delve", dng = "dungeon",
	mplus = "dungeon", boss = "raid", toy = "coll", mount = "coll", pet = "coll", renown = "rep", rep = "rep",
	friend = "social", guild = "social", club = "social" }
local CATEGORY_OF_ENTRY = { delve = "delve", party = "dungeon", raid = "raid" }
-- Sorties de patchs (Retail, date des serveurs européens : le mercredi), écrites en vert dans
-- l'en-tête du jour, pour les mois affichés et, à venir, toujours (case « Ext » en bas à droite de
-- la fenêtre, PolypodeHistoireDB.showPatches). **À compléter à chaque patch**, dès sa date officielle
-- (Mamytwink / Wowhead, nom officiel français s'il y en a un) ; 12.1.7 « Échos du Noyau-monde » :
-- pas encore daté au 16/10/2026.
local PATCHES = {
	["2026-01-21"] = L["Patch 12.0.0 (pré-patch de Midnight)"],
	["2026-02-11"] = L["Patch 12.0.1"],
	["2026-03-03"] = L["Sortie de Midnight"],
	["2026-04-22"] = L["Patch 12.0.5"],
	["2026-06-17"] = L["Patch 12.0.7 « Révélations »"],
	["2026-08-12"] = L["Patch 12.1.0 « La malédiction d'Ula'tek »"],
	["2026-08-19"] = L["Saison 2 de Midnight"],
	["2026-10-14"] = L["Patch 12.1.5 « La Promesse de demain »"],
}
local PATCH_COLOR = "|cff40ff40"
-- Table propre à Retail (WoW Forever a ses propres versions).
local IS_RETAIL = (select(4, GetBuildInfo()) or 0) >= 100000
-- Mois en tête de ligne, mois dans une phrase (« lundi 21 octobre » : minuscule en français, pas en
-- anglais ni en allemand), jours de la semaine.
local MONTHS = { L["Janvier"], L["Février"], L["Mars"], L["Avril"], L["Mai"], L["Juin"], L["Juillet"], L["Août"],
	L["Septembre"], L["Octobre"], L["Novembre"], L["Décembre"] }
local MONTHS_IN_TEXT = { L["janvier"], L["février"], L["mars"], L["avril"], L["mai"], L["juin"], L["juillet"], L["août"],
	L["septembre"], L["octobre"], L["novembre"], L["décembre"] }
local WEEKDAYS = { L["Dimanche"], L["Lundi"], L["Mardi"], L["Mercredi"], L["Jeudi"], L["Vendredi"], L["Samedi"] }

local frame, listPanel

local function Settings()
	PolypodeHistoireDB = PolypodeHistoireDB or {}
	PolypodeHistoireDB.open = PolypodeHistoireDB.open or {}
	PolypodeHistoireDB.filters = PolypodeHistoireDB.filters or {}
	if PolypodeHistoireDB.showPatches == nil then
		PolypodeHistoireDB.showPatches = true
	end
	if PolypodeHistoireDB.view ~= "frise" then
		PolypodeHistoireDB.view = "liste"
	end
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

-- Événement à ignorer : renom sans nom (compteur technique caché, ex. 2739 « Gouffres : conversion
-- de fragments de clé de coffre », noté avant la 1.10.2).
local function IsNoise(event)
	local _, _, kind, fields = ns.Parse(event)
	return kind == "renown" and (fields[6] or "") == ""
end

-- Événements d'un jour retenus par les filtres (tous si aucun n'est coché), sans les événements à
-- ignorer.
local function Filtered(list)
	local filters = Settings().filters
	local any = next(filters) ~= nil
	local kept = {}
	for _, event in ipairs(list) do
		if not IsNoise(event) then
			local category = any and EventCategory(event)
			if not any or (category and filters[category]) then
				kept[#kept + 1] = event
			end
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
	return key >= today:sub(1, #key) -- période en cours, ou à venir (patch annoncé)
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

-- Nom d'un jouet, d'une monture ou d'une mascotte relevé sans nom (données pas encore chargées).
local function CollectionName(kind, id)
	id = tonumber(id)
	if not id then
		return nil
	elseif kind == "toy" then
		return C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
	elseif kind == "mount" then
		return C_MountJournal and C_MountJournal.GetMountInfoByID and (C_MountJournal.GetMountInfoByID(id))
	end
	return C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID and (C_PetJournal.GetPetInfoBySpeciesID(id))
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
		return L["< 1 min"]
	elseif minutes < 60 then
		return L["%d min"]:format(minutes)
	end
	return L["%d h %02d"]:format(math.floor(minutes / 60), minutes % 60)
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

-- Nom entre guillemets (ceux de la langue d'affichage), en jaune.
local function Quoted(text)
	return L["« %s »"]:format("|cffffd200" .. tostring(text) .. "|r")
end

-- Texte d'une ligne : noms des personnages puis l'action. Deux formats par événement, singulier et
-- pluriel (verbe accordé quand ils sont plusieurs), le premier %s recevant les noms.
local function EventText(line)
	local f = line.fields
	local names = {}
	for _, key in ipairs(line.keys) do
		names[#names + 1] = CharName(key)
	end
	local who = table.concat(names, ", ")
	local plural = #line.keys > 1
	local function say(one, many, ...)
		return (plural and many or one):format(who, ...)
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
		return say(L["%s se connecte"], L["%s se connectent"])
	elseif kind == "out" then
		local played = #line.keys == 1 and line.durations[1] and (" (" .. DurationText(line.durations[1]) .. ")") or ""
		return say(L["%s |cff999999se déconnecte%s|r"], L["%s |cff999999se déconnectent%s|r"], played)
	elseif kind == "grp" then
		return L["|cff40ff40L'équipe %s se groupe|r (%s personnages)"]:format(Quoted(f[4]), f[5] or "?")
	elseif kind == "lvl" then
		return say(L["%s atteint le |cffffd200niveau %s|r"], L["%s atteignent le |cffffd200niveau %s|r"], f[4] or "?")
	elseif kind == "ach" then
		return say(L["%s obtient le haut fait %s"], L["%s obtiennent le haut fait %s"], Quoted(AchievementName(f[4])))
	elseif kind == "ilvl" then
		local gain = (tonumber(f[4]) or 0) - (tonumber(f[5]) or 0)
		return say(L["%s passe au |cffffd200niveau d'objet %s|r"], L["%s passent au |cffffd200niveau d'objet %s|r"],
			f[4] or "?") .. " |cff40ff40(+" .. gain .. ")|r"
	elseif kind == "toy" or kind == "mount" or kind == "pet" then
		local name = Quoted(f[5] and f[5] ~= "" and f[5] or CollectionName(kind, f[4]) or L["n° %s"]:format(tostring(f[4])))
		if kind == "toy" then
			return say(L["%s obtient le jouet %s"], L["%s obtiennent le jouet %s"], name)
		elseif kind == "mount" then
			return say(L["%s obtient la monture %s"], L["%s obtiennent la monture %s"], name)
		end
		return say(L["%s obtient la mascotte %s"], L["%s obtiennent la mascotte %s"], name)
	elseif kind == "friend" then
		local added = f[5] == "+"
		if f[6] == "b" then
			-- Ami Battle.net : commun au compte, sans nom de personnage (détail dans l'infobulle).
			return (added and L["|cff82c5ffAmi Battle.net ajouté|r : %s"] or L["|cff82c5ffAmi Battle.net retiré|r : %s"])
				:format(Quoted(f[4]))
		end
		if added then
			return say(L["%s ajoute %s à ses amis"], L["%s ajoutent %s à leurs amis"], Quoted(f[4]))
		end
		return say(L["%s retire %s de ses amis"], L["%s retirent %s de leurs amis"], Quoted(f[4]))
	elseif kind == "guild" then
		if f[5] == "+" then
			return say(L["%s rejoint la guilde %s"], L["%s rejoignent la guilde %s"], Quoted(f[4]))
		end
		return say(L["%s quitte la guilde %s"], L["%s quittent la guilde %s"], Quoted(f[4]))
	elseif kind == "club" then
		local added = f[5] == "+"
		if f[6] == "b" then
			return (added and L["|cff82c5ffCommunauté Battle.net rejointe|r : %s"]
				or L["|cff82c5ffCommunauté Battle.net quittée|r : %s"]):format(Quoted(f[4]))
		end
		if added then
			return say(L["%s rejoint la communauté %s"], L["%s rejoignent la communauté %s"], Quoted(f[4]))
		end
		return say(L["%s quitte la communauté %s"], L["%s quittent la communauté %s"], Quoted(f[4]))
	elseif kind == "renown" then
		return say(L["%s atteint le |cffffd200renom %s|r auprès de %s"], L["%s atteignent le |cffffd200renom %s|r auprès de %s"],
			f[5] or "?", Quoted(f[6] ~= "" and f[6] or "?"))
	elseif kind == "rep" then
		return say(L["%s devient %s auprès de %s"], L["%s deviennent %s auprès de %s"], Quoted(f[5] or "?"),
			Quoted(f[6] ~= "" and f[6] or "?"))
	elseif kind == "enter" then
		local difficulty = f[6] ~= "delve" and DifficultyName(f[5])
		local text
		if f[6] == "delve" then
			text = say(L["%s |cff999999entre dans le gouffre|r %s"], L["%s |cff999999entrent dans le gouffre|r %s"], Quoted(f[4]))
		elseif f[6] == "party" then
			text = say(L["%s |cff999999entre dans le donjon|r %s"], L["%s |cff999999entrent dans le donjon|r %s"], Quoted(f[4]))
		elseif f[6] == "raid" then
			text = say(L["%s |cff999999entre dans le raid|r %s"], L["%s |cff999999entrent dans le raid|r %s"], Quoted(f[4]))
		else
			text = say(L["%s |cff999999entre dans l'instance|r %s"], L["%s |cff999999entrent dans l'instance|r %s"],
				Quoted(f[4]))
		end
		return text .. (difficulty and (" |cff999999(" .. difficulty .. ")|r") or "")
	elseif kind == "delve" then
		-- Palier « 0 » : inconnu (anciens événements, lus dans les données du groupe à l'entrée).
		local tier = f[5] and f[5] ~= "" and f[5] ~= "0" and L["palier %s"]:format(f[5]) or nil
		local name = f[6] and f[6] ~= "" and L["%s : %s"]:format(Quoted(f[4]), Quoted(f[6])) or Quoted(f[4])
		return say(L["%s termine le gouffre %s"], L["%s terminent le gouffre %s"], name) .. details(tier)
	elseif kind == "dng" then
		return say(L["%s termine le donjon %s"], L["%s terminent le donjon %s"], Quoted(f[4])) .. details(DifficultyName(f[5]))
	elseif kind == "mplus" then
		local timed = f[6] == "1" and "|cff40ff40" .. L["dans les temps"] .. "|r" or "|cffff4040" .. L["hors temps"] .. "|r"
		return say(L["%s termine la clé %s |cffffd200+%s|r"], L["%s terminent la clé %s |cffffd200+%s|r"], Quoted(f[4]),
			f[5] or "?") .. details(timed)
	elseif kind == "boss" then
		return say(L["%s vainc %s"], L["%s vainquent %s"], Quoted(f[4])) .. " |cff999999"
			.. details(f[6] or "?", DifficultyName(f[5])) .. "|r"
	end
	return L["%s : %s"]:format(who, kind)
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
	-- Totaux par année et par mois.
	local totals = {}
	for _, day in ipairs(days) do
		local n = #lists[day]
		totals[day:sub(1, 4)] = (totals[day:sub(1, 4)] or 0) + n
		totals[day:sub(1, 7)] = (totals[day:sub(1, 7)] or 0) + n
	end
	-- Jours de sortie d'un patch dans un mois affiché, ou à venir, même sans événement.
	local today = ns.DayOf(GetServerTime())
	local patches = IS_RETAIL and Settings().showPatches and PATCHES or {}
	for day in pairs(patches) do
		if (totals[day:sub(1, 7)] or day > today) and #(lists[day] or {}) == 0 then
			lists[day] = {}
			days[#days + 1] = day
		end
	end
	table.sort(days, function(a, b)
		return a > b
	end)
	local durations = SessionDurations(ns.GetDays())
	local items = {}
	local year, month
	for _, day in ipairs(days) do
		if day:sub(1, 4) ~= year then
			year, month = day:sub(1, 4), nil
			items[#items + 1] = { header = 1, key = year, label = year, count = totals[year] or 0 }
		end
		if IsOpen(year) then
			if day:sub(1, 7) ~= month then
				month = day:sub(1, 7)
				items[#items + 1] = { header = 2, key = month, label = MONTHS[tonumber(day:sub(6, 7))] .. " " .. year,
					count = totals[month] or 0 }
			end
			if IsOpen(month) then
				local t = time({ year = tonumber(year), month = tonumber(day:sub(6, 7)), day = tonumber(day:sub(9, 10)),
					hour = 12 })
				local list = lists[day]
				items[#items + 1] = { header = 3, key = day,
					label = L["%s %d %s"]:format(WEEKDAYS[tonumber(date("%w", t)) + 1], tonumber(day:sub(9, 10)),
						MONTHS_IN_TEXT[tonumber(day:sub(6, 7))]), count = #list, patch = patches[day] }
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
		if item.header == 3 and item.count == 0 then
			mark = " " -- jour de patch sans événement : rien à déplier
		end
		local isFuture = item.header == 3 and item.key > ns.DayOf(GetServerTime())
		local text = INDENT[item.header] .. "|cff999999" .. mark .. "|r " .. color .. item.label .. "|r"
		if item.count > 0 then
			text = text .. "  |cff999999(" .. item.count .. ")|r"
		end
		if item.patch then
			text = text .. "  " .. PATCH_COLOR .. item.patch .. (isFuture and " " .. L["(à venir)"] or "") .. "|r"
		end
		return text
	end
	return "            |cff999999" .. date("%H:%M", item.time) .. "|r  " .. EventText(item)
end

local function ItemTooltip(item)
	if item.header then
		local lines = { item.label }
		if item.patch then
			lines[#lines + 1] = PATCH_COLOR .. item.patch .. "|r " .. L["(serveurs européens)"]
		end
		lines[#lines + 1] = L["%d événement(s)"]:format(item.count)
		if item.count > 0 then
			lines[#lines + 1] = IsOpen(item.key) and L["Clic : replier"] or L["Clic : déplier"]
		end
		return lines
	end
	local lines = { date("%d/%m/%Y", item.time) }
	for i, key in ipairs(item.keys) do
		local played = item.durations[i] and ("  |cff999999(" .. DurationText(item.durations[i]) .. ")|r") or ""
		lines[#lines + 1] = { CharName(key), date("%H:%M:%S", item.times[i]) .. played }
	end
	if item.kind == "ach" then
		lines[#lines + 1] = L["Clic : ouvrir le haut fait"]
	end
	lines[#lines + 1] = L["Clic droit : supprimer"]
	return lines
end

-- SUPPRESSION -------------------------------------------------------------------------------------

StaticPopupDialogs["POLYPODE_HISTOIRE_DELETE"] = {
	text = "%s",
	button1 = DELETE or L["Supprimer"],
	button2 = CANCEL or L["Annuler"],
	OnAccept = function(_, data)
		ns.Delete(data)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local function AskDelete(item)
	local count = #item.events
	StaticPopup_Show("POLYPODE_HISTOIRE_DELETE", L["Supprimer cette entrée du journal ?"] .. "\n\n"
		.. date(L["%d/%m/%Y %H:%M"], item.time) .. "  " .. EventText(item) .. "\n\n"
		.. (count > 1 and L["%d événements (un par personnage) seront retirés, ici et sur les clients connectés."]:format(count)
			or L["Elle sera retirée, ici et sur les clients connectés."]), nil, item.events)
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
	button1 = L["Exporter"],
	button2 = CANCEL or L["Annuler"],
	OnAccept = function()
		local ok, result = ns.Export()
		if ok then
			UIErrorsFrame:AddMessage(L["Polypode Histoire : %s événement(s) archivé(s), écrits à la déconnexion ou au /reload."]
				:format(result), 0.25, 1, 0.25)
		else
			UIErrorsFrame:AddMessage(L["Polypode Histoire : %s."]:format(result), 1, 0.1, 0.1)
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local function AskExport()
	local days, events, cutoff = ns.ExportableDays()
	if days == 0 then
		UIErrorsFrame:AddMessage(L["Polypode Histoire : rien à exporter (seuls le mois en cours et le précédent sont "
			.. "dans le journal)."], 1, 0.82, 0)
		return
	end
	StaticPopup_Show("POLYPODE_HISTOIRE_EXPORT", string.format(L["Exporter %d jour(s) (%d événements) antérieurs au "
		.. "%s vers l'archive (Polypode Histoire Archive) ?\n\nL'archive est complétée, jamais remplacée ; ces "
		.. "jours sont ensuite retirés du journal, ici et sur les clients connectés."], days, events,
		date(L["%d/%m/%Y"], time({ year = tonumber(cutoff:sub(1, 4)), month = tonumber(cutoff:sub(6, 7)), day = 1, hour = 12 }))))
end

-- FENÊTRE -----------------------------------------------------------------------------------------

local function HeaderText()
	local size, count = ns.GetSize()
	local color = size >= ns.ALERT_SIZE and "|cffff4040" or (size >= ns.WARN_SIZE and "|cffff8000" or "|cff999999")
	local text = L["Journal commun"] .. "  " .. color .. L["· %d événements · %d Ko"]:format(count, math.ceil(size / 1024))
	if size >= ns.WARN_SIZE then
		text = text .. " · " .. L["export conseillé"]
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
	-- Taille gardée, ramenée à celle de l'écran (une taille enregistrée trop grande la dépasserait).
	frame:SetSize(math.min(math.max(settings.width or DEFAULT_WIDTH, MIN_WIDTH), math.max(UIParent:GetWidth(), MIN_WIDTH)),
		math.min(math.max(settings.height or DEFAULT_HEIGHT, MIN_HEIGHT), math.max(UIParent:GetHeight(), MIN_HEIGHT)))
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

	-- Bas de la fenêtre : cases de filtre à gauche, case « Ext » (sorties des patchs et extensions) à
	-- droite, contre la poignée de redimensionnement ; titre centré dans la barre de titre.
	local patchCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	patchCheck:SetSize(22, 22)
	patchCheck:SetChecked(settings.showPatches)
	patchCheck:SetScript("OnClick", function(self)
		Settings().showPatches = self:GetChecked() and true or false
		ns.Refresh()
	end)
	patchCheck:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(L["Extensions et patchs"])
		GameTooltip:AddLine(L["Cochée : les jours de sortie des patchs et des extensions sont écrits en vert avec "
			.. "leur nom (date des serveurs européens), dans les mois affichés, et ceux annoncés à venir."], 1, 1, 1, true)
		if not IS_RETAIL then
			GameTooltip:AddLine(L["Retail seulement."], 1, 0.25, 0.25, true)
		end
		ShowTooltip()
	end)
	patchCheck:SetScript("OnLeave", GameTooltip_Hide)
	if P.SkinCheckBox then
		P.SkinCheckBox(patchCheck)
	end
	local patchText = patchCheck.Text or patchCheck.text
	if patchText then
		patchText:SetText(L["Ext"])
		patchText:SetFontObject("GameFontHighlightSmall")
		patchText:ClearAllPoints()
		patchText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 13)
		patchCheck:SetPoint("RIGHT", patchText, "LEFT", -3, 0)
		patchCheck:SetHitRectInsets(0, -(patchText:GetStringWidth() + 3), 0, 0)
	else
		patchCheck:SetPoint("BOTTOMRIGHT", -24, 8)
	end
	frame.patchCheck = patchCheck

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -14)
	title:SetText(L["Histoire"])
	frame.TitleText = title
	frame.filterChecks = {}
	local previous
	for _, filter in ipairs(FILTERS) do
		local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
		check:SetSize(22, 22)
		if previous then
			check:SetPoint("LEFT", previous, "RIGHT", 8, 0)
		else
			check:SetPoint("BOTTOMLEFT", 10, 8)
		end
		check:SetChecked(settings.filters[filter.key] == true)
		check:SetScript("OnClick", function(self)
			Settings().filters[filter.key] = self:GetChecked() and true or nil
			ns.Refresh()
		end)
		check:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(filter.label)
			GameTooltip:AddLine(filter.tip, 1, 1, 1, true)
			GameTooltip:AddLine(L["Cochée : n'affiche que ces événements (avec les autres cases cochées). Aucune "
				.. "case cochée : tout le journal."], 0.7, 0.7, 0.7, true)
			ShowTooltip()
		end)
		check:SetScript("OnLeave", GameTooltip_Hide)
		if P.SkinCheckBox then
			P.SkinCheckBox(check)
		end
		-- Libellé posé après le skin (EllesmereUI le collait à son cadre).
		local text = check.Text or check.text
		if text then
			text:SetText(filter.short)
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
	listPanel:SetPoint("BOTTOMRIGHT", -12, 34)
	P.CreateScrollList(listPanel, FormatItem, nil, { onClick = OnItemClick, tooltip = ItemTooltip })

	-- Boutons à droite de l'en-tête du panneau : « Exporter », puis « Tout replier / déplier ».
	local exportBtn = MakeButton(listPanel, L["Exporter"], 70, AskExport, function()
		local days, events = ns.ExportableDays()
		return L["Archive les mois antérieurs au mois précédent (%d jour(s), %d événements) dans Polypode Histoire "
			.. "Archive, puis les retire du journal pour l'alléger. L'archive est complétée à chaque export, jamais "
			.. "remplacée."]:format(days, events)
	end)
	exportBtn:SetPoint("TOPRIGHT", -6, -4)
	local collapseBtn = MakeButton(listPanel, L["Tout replier"], 96, function(self)
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
		return self.collapseAll and L["Replie toutes les années, mois et jours affichés."]
			or L["Déplie toutes les années, tous les mois et tous les jours."]
	end)
	collapseBtn:SetPoint("RIGHT", exportBtn, "LEFT", -4, 0)
	frame.collapseButton = collapseBtn
	listPanel.header:ClearAllPoints()
	listPanel.header:SetPoint("TOPLEFT", 10, -8)
	listPanel.header:SetPoint("RIGHT", collapseBtn, "LEFT", -6, 0)

	-- Vues « Liste » / « Frise » (boutons en haut à gauche, choix gardé dans PolypodeHistoireDB.view) :
	-- la frise (Frise.lua) prend la place de la liste ; filtres et case « Ext » communs aux deux.
	frame.viewButtons = {}
	local previousView
	for _, view in ipairs({ { key = "liste", label = L["Liste"], tip = L["Journal en arbre Année > Mois > Jour."] },
		{ key = "frise", label = L["Frise"], tip = L["Frise chronologique horizontale : jour, semaine, mois ou tout le "
			.. "journal ; icônes, infobulles, sessions de chaque personnage."] } }) do
		local button = MakeButton(frame, view.label, 50, function()
			Settings().view = view.key
			ns.Refresh()
		end, view.tip)
		if previousView then
			button:SetPoint("LEFT", previousView, "RIGHT", 2, 0)
		else
			button:SetPoint("TOPLEFT", 12, -12)
		end
		button.view = view.key
		frame.viewButtons[#frame.viewButtons + 1] = button
		previousView = button
	end
	if ns.BuildFrise then
		frame.frisePanel = ns.BuildFrise(frame)
		frame.frisePanel:SetPoint("TOPLEFT", 12, -36)
		frame.frisePanel:SetPoint("BOTTOMRIGHT", -12, 34)
		frame.frisePanel:Hide()
	end

	-- Poignée de redimensionnement (taille gardée).
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -4, 4)
	grip:SetFrameLevel(frame:GetFrameLevel() + 10)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	-- Pendant le redimensionnement, le coin haut-gauche reste fixe (ancre TOPLEFT au lieu du centre)
	-- et la taille ne dépasse pas la place jusqu'aux bords de l'écran : sinon, la fenêtre étant
	-- retenue dans l'écran, le jeu la repoussait et elle s'agrandissait d'un coup hors de l'écran.
	-- Départ depuis la souris (alwaysStartFromMouse, comme les poignées de Blizzard) : pas de saut.
	grip:SetScript("OnMouseDown", function()
		local left, top = frame:GetLeft(), frame:GetTop()
		if left and top then
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
			if frame.SetResizeBounds then
				frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, math.max(UIParent:GetWidth() - left, MIN_WIDTH),
					math.max(top, MIN_HEIGHT))
			end
		end
		frame:StartSizing("BOTTOMRIGHT", true)
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		Settings().width, Settings().height = frame:GetSize()
	end)
	-- Double-clic sur la barre de titre : taille par défaut (Polypode 2.12).
	if P.EnableTitleDoubleClick then
		P.EnableTitleDoubleClick(frame, function()
			Settings().width, Settings().height = DEFAULT_WIDTH, DEFAULT_HEIGHT
			frame:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
		end)
	end

	P.ui.histoireFrame = frame
	if P.SkinFrame then
		P.SkinFrame(frame)
	end
	if P.SkinPanel then
		P.SkinPanel(listPanel)
	end
end

-- Remplit la liste (ou la frise, selon la vue), si la fenêtre est ouverte.
function ns.Refresh()
	if not frame or not frame:IsShown() then
		return
	end
	local frise = Settings().view == "frise" and frame.frisePanel
	for _, button in ipairs(frame.viewButtons) do
		if button.view == (frise and "frise" or "liste") then
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
	end
	if frise then
		listPanel:Hide()
		frame.frisePanel:Show()
		ns.RefreshFrise()
		return
	end
	if frame.frisePanel then
		frame.frisePanel:Hide()
	end
	listPanel:Show()
	local items = BuildItems()
	frame.items = items
	local anyOpen = false
	for _, item in ipairs(items) do
		anyOpen = anyOpen or (item.header and IsOpen(item.key))
	end
	frame.collapseButton.collapseAll = anyOpen
	frame.collapseButton:SetText(anyOpen and L["Tout replier"] or L["Tout déplier"])
	listPanel.header:SetText(HeaderText())
	listPanel.emptyText:SetText(next(Settings().filters) and L["Aucun événement pour les filtres cochés."]
		or L["Aucun événement noté pour l'instant."])
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

-- Montre un jour dans la liste (clic sur une icône de la frise) : vue Liste, année, mois et jour
-- dépliés.
local function OpenDay(day)
	local settings = Settings()
	settings.view = "liste"
	settings.open[day:sub(1, 4)], settings.open[day:sub(1, 7)], settings.open[day] = true, true, true
	ns.Refresh()
end

-- Outils partagés avec Frise.lua (chargé après ce fichier).
ns.H = {
	Settings = Settings,
	Filtered = Filtered,
	EventText = EventText,
	DayLines = DayLines,
	SessionDurations = SessionDurations,
	CharName = CharName,
	DurationText = DurationText,
	ShowTooltip = ShowTooltip,
	MakeButton = MakeButton,
	OpenDay = OpenDay,
	PATCHES = PATCHES,
	IS_RETAIL = IS_RETAIL,
	MONTHS = MONTHS,
	WEEKDAYS = WEEKDAYS,
	MONTHS_IN_TEXT = MONTHS_IN_TEXT,
}

-- INTÉGRATION À POLYPODE --------------------------------------------------------------------------

if P.AddTitleButton then
	P.AddTitleButton({
		text = L["Histoire"],
		width = 70,
		onClick = function()
			P.ToggleHistoire()
		end,
		tooltip = { L["Polypode Histoire"], L["Journal commun de tous les personnages joués : connexions, groupes "
			.. "d'équipe, gouffres, donjons, clés M+, boss de raid, hauts faits, niveaux, niveau d'objet."] },
		onCreate = function(button)
			P.ui.histoireButton = button
		end,
	})
end

if P.RegisterSlashCommand then
	P.RegisterSlashCommand("histoire", P.ToggleHistoire, L["journal commun des personnages (Polypode Histoire)"])
end
