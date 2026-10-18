-- Polypode Histoire: Journal — relevé des événements, stockage, synchro entre clients, export

local _, ns = ...
local P = Polypode -- dépendance obligatoire (## Dependencies: Polypode), chargée avant nous

-- JOURNAL COMMUN : chaque client note les événements de SON personnage, les envoie aux clients
-- connectés (message HIST) et garde aussi ceux qu'il reçoit ; tous les clients tiennent donc le
-- même journal. Les comptes partagent souvent un seul dossier SavedVariables (jonctions) : le
-- dernier client qui quitte écrit le fichier, d'où la synchro systématique et, à chaque client qui
-- s'annonce (HELLO/HI), le renvoi des événements de la session en cours.
--
-- Événement = texte « heure~nom-royaume~type~champ1~champ2... » (heure serveur, GetServerTime),
-- rangé par jour local dans PolypodeHistoireData.days["AAAA-MM-JJ"], trié par heure ; le texte
-- entier sert d'identifiant (doublon ignoré). Types :
--   in / out          connexion / déconnexion
--   grp  équipe~n     l'équipe s'est groupée au complet (noté par son leader)
--   lvl  niveau       niveau atteint
--   ach  id           haut fait obtenu (pas ceux déjà obtenus par le compte)
--   ilvl nouveau~ancien  niveau d'objet équipé, sans décimales, quand il dépasse le plus haut connu
--   enter nom~difficulté~genre  entrée dans un gouffre, un donjon ou un raid (genre : delve / party / raid)
--   delve nom~palier~section~durée  gouffre terminé (section : étape du scénario, pour les gouffres en
--                     plusieurs parties ; palier « 0 » dans les anciens événements = inconnu)
--   dng  nom~difficulté~durée  donjon terminé (dernier boss du Journal des donjons vaincu, hors clé M+)
--   mplus nom~niveau~àTemps(1/0)~améliorations~durée  clé mythique+ terminée
--   boss nom~difficulté~raid~durée  boss de raid vaincu
--   toy  id~nom       jouet obtenu (id d'objet)
--   mount id~nom      monture obtenue (mountID)
--   pet  id~nom       mascotte obtenue (speciesID)
--   renown id~niveau~faction  palier de renom atteint (faction majeure)
--   rep  id~rang~faction~niveau  rang de réputation atteint (rang = texte du jeu : « Révéré », rang
--                     d'amitié… ; niveau = numéro du rang), noté seulement en montant
--   friend nom~+/-~c/b  ami ajouté (+) ou retiré (-) : c = ami du personnage, b = ami Battle.net (BattleTag
--                     sans son numéro)
--   guild nom~+/-     guilde rejointe ou quittée
--   club nom~+/-~c/b  communauté rejointe ou quittée (c = de personnage, b = Battle.net)
--   durée : secondes depuis l'entrée, ou depuis le précédent gouffre / donjon / boss terminé dans la
--   même instance (clé M+ : temps du chrono) ; vide si inconnue (absente des anciens événements).
-- Messages : HIST:token:E:<événement> (nouvel événement), HIST:token:R:<événement> (retrait :
-- déconnexion annulée, déco-reco ou session courte : seulement de son personnage),
-- HIST:token:D:<événement> (supprimé à la main, clic droit : de n'importe quel client de l'équipe),
-- HIST:token:P:<AAAA-MM-JJ> (export : jours antérieurs retirés).

local MESSAGE_TYPE = "HIST"
local SEP = "~"
local FORMAT = 1
local LINE_OVERHEAD = 16 -- octets par événement dans le fichier en plus du texte (« "...", -- [n] »)
local DAY_OVERHEAD = 30 -- octets par jour (clé et accolades)
ns.WARN_SIZE = 2 * 1024 * 1024 -- avertissement : export conseillé
ns.ALERT_SIZE = 5 * 1024 * 1024 -- alerte (rouge)
local SESSION_RESEND_MAX = 100 -- événements de la session renvoyés à un client qui s'annonce
-- Événements retirés, gardés dans store.deleted ([événement] = "D:<heure>" suppression à la main,
-- "R:<heure>" retrait automatique) pour qu'un lecteur du fichier (site Histoire, historique cumulé)
-- les retire aussi ; oubliés au chargement après DELETED_KEEP secondes.
local DELETED_KEEP = 120 * 86400
local GROUP_MERGE_DELAY = 2 -- secondes : regroupe les GROUP_ROSTER_UPDATE rapprochés
local ILVL_DELAY = 3 -- secondes : regroupe les changements d'équipement
local SHORT_DELAY = 180 -- secondes : déco-reco ou session plus courtes ne sont pas notées
local REENTRY_DELAY = 900 -- secondes : retour dans la même instance (mort, sortie) sans nouvelle entrée
local COMPLETION_KINDS = { delve = true, dng = true, mplus = true, boss = true }
local DELVES_HEADER_WIDGET = Enum and Enum.UIWidgetVisualizationType
	and Enum.UIWidgetVisualizationType.ScenarioHeaderDelves or 29 -- en-tête de scénario d'un gouffre

local store -- = PolypodeHistoireData : { format, days = { [jour] = { événements } }, ilvl = { [clé] = n }, cutoff }
local seen = {} -- [événement] = true, index des doublons (construit au chargement)
local sessionEvents = {} -- événements du personnage joué pendant la session (renvoyés aux clients qui s'annoncent)
local size = 0 -- taille estimée du journal dans le fichier (octets)
local count = 0 -- nombre d'événements
local withdrawn = {} -- [événement] = "R" / "D", retirés pendant la session (renvoyés aux clients qui s'annoncent)
local reloading -- /reload en cours : PLAYER_LOGOUT n'est pas une déconnexion
local loginEvent, loginTime -- événement « in » de la session (nil si reconnexion rapide) et son heure
local visit -- instance en cours : { id, name, start, last } (UpdateVisit) ; left / leftAt : celle qu'on vient de quitter
local left, leftAt
local delveState -- gouffre en cours : { tier, section } relevés pendant le scénario (UpdateDelveState)
local loggedOut -- déconnexion traitée par Logout / Quit (annulée par CancelLogout) : événement « out »
-- noté, "short" si la session était trop courte (connexion retirée, rien de noté), ou "skip" (idem,
-- connexion déjà supprimée à la main)

-- OUTILS ------------------------------------------------------------------------------------------

-- Champ sûr : ni séparateur, ni code de couleur, ni saut de ligne.
local function Clean(value)
	return (tostring(value == nil and "" or value):gsub("[~|\r\n]", " "))
end

local function DayOf(time)
	return date("%Y-%m-%d", time)
end
ns.DayOf = DayOf

-- Découpe un événement : heure (nombre), clé, type, puis les champs.
local function Parse(event)
	local fields = { strsplit(SEP, event) }
	return tonumber(fields[1]), fields[2], fields[3], fields
end
ns.Parse = Parse

local function Refresh()
	if ns.Refresh then
		ns.Refresh()
	end
end

-- STOCKAGE ----------------------------------------------------------------------------------------

-- Ajoute un événement à son jour (trié par heure) ; faux si doublon, mal formé, antérieur au
-- dernier export ou supprimé à la main. Retiré automatiquement (« R ») : refusé, sauf restore
-- (événement renvoyé par son personnage ou déconnexion annulée), qui efface la trace du retrait.
local function Insert(event, restore)
	if seen[event] then
		return false
	end
	local deleted = store.deleted and store.deleted[event]
	if deleted then
		if deleted:sub(1, 1) == "D" or not restore then
			return false
		end
		store.deleted[event] = nil
	end
	local time, key, kind = Parse(event)
	if not time or not key or not kind then
		return false
	end
	local day = DayOf(time)
	if store.cutoff and day < store.cutoff then
		return false
	end
	local list = store.days[day]
	if not list then
		list = {}
		store.days[day] = list
		size = size + DAY_OVERHEAD
	end
	local index = #list + 1
	while index > 1 and (tonumber((strsplit(SEP, list[index - 1]))) or 0) > time do
		index = index - 1
	end
	table.insert(list, index, event)
	seen[event] = true
	size = size + #event + LINE_OVERHEAD
	count = count + 1
	return true
end

-- Retire un événement (déconnexion annulée).
local function Remove(event)
	if not seen[event] then
		return
	end
	local list = store.days[DayOf(Parse(event))]
	for i = #(list or {}), 1, -1 do
		if list[i] == event then
			table.remove(list, i)
			break
		end
	end
	seen[event] = nil
	size = size - #event - LINE_OVERHEAD
	count = count - 1
end

-- Recalcule l'index et la taille (chargement, export).
local function Reindex()
	seen, size, count = {}, 0, 0
	for _, list in pairs(store.days) do
		size = size + DAY_OVERHEAD
		for _, event in ipairs(list) do
			seen[event] = true
			size = size + #event + LINE_OVERHEAD
			count = count + 1
		end
	end
end

function ns.GetDays()
	return store and store.days or {}
end

function ns.GetSize()
	return size, count
end

-- SYNCHRO -----------------------------------------------------------------------------------------

local function Send(kind, payload, target)
	local token = P.GetTeamToken and P.GetTeamToken()
	if not token or not P.WhisperOnline then
		return
	end
	local message = MESSAGE_TYPE .. ":" .. token .. ":" .. kind .. ":" .. payload
	if #message <= (P.MAX_MESSAGE_LENGTH or 255) then
		P.WhisperOnline(message, target)
	end
end

-- Note un événement du personnage joué et l'envoie aux clients connectés.
local function Record(kind, ...)
	local parts = { GetServerTime(), P.GetCharKey(), kind }
	for i = 1, select("#", ...) do
		parts[#parts + 1] = Clean((select(i, ...)))
	end
	local event = table.concat(parts, SEP)
	if Insert(event) then
		sessionEvents[#sessionEvents + 1] = event
		Send("E", event)
		Refresh()
	end
	return event
end

-- Garde la trace d'un événement retiré (kind "D" ou "R" ; une suppression à la main l'emporte).
local function MarkDeleted(event, kind)
	local known = store.deleted[event]
	if kind == "D" or not known then
		store.deleted[event] = kind .. ":" .. GetServerTime()
	end
end

-- Retire un événement du personnage joué, ici et chez les clients connectés (renvoyé à ceux qui
-- s'annoncent ensuite).
local function Withdraw(event)
	Remove(event)
	MarkDeleted(event, "R")
	withdrawn[event] = withdrawn[event] or "R"
	Send("R", event)
	Refresh()
end

-- Supprime des événements à la main (clic droit dans la fenêtre), ici et chez les clients connectés.
function ns.Delete(list)
	for _, event in ipairs(list) do
		Remove(event)
		MarkDeleted(event, "D")
		withdrawn[event] = "D"
		Send("D", event)
	end
	Refresh()
end

-- Purge des jours antérieurs à cutoff (export, ici ou sur un autre client).
local function ApplyCutoff(cutoff)
	if not cutoff or (store.cutoff and store.cutoff >= cutoff) then
		return
	end
	store.cutoff = cutoff
	for day in pairs(store.days) do
		if day < cutoff then
			store.days[day] = nil
		end
	end
	Reindex()
	Refresh()
end

-- Message reçu (token déjà vérifié par Polypode) : « type:contenu ».
local function OnMessage(rest, sender)
	local kind, payload = strsplit(":", rest or "", 2)
	if not payload or not store then
		return
	end
	if kind == "P" then
		if payload:match("^%d%d%d%d%-%d%d%-%d%d$") then
			ApplyCutoff(payload)
		end
		return
	end
	if kind == "D" then
		-- Suppression à la main : de n'importe quel client de l'équipe (token vérifié).
		if seen[payload] then
			Remove(payload)
			Refresh()
		end
		MarkDeleted(payload, "D")
		withdrawn[payload] = "D"
		return
	end
	-- Événement : seulement celui du personnage qui l'envoie.
	local _, key = Parse(payload)
	if not key or not (P.IsSender and P.IsSender(sender, key)) then
		return
	end
	if kind == "E" then
		-- Renvoyé par son personnage : un retrait automatique noté ici est annulé.
		if Insert(payload, true) then
			Refresh()
		end
	elseif kind == "R" then
		Remove(payload)
		MarkDeleted(payload, "R")
		Refresh()
	end
end

-- Un client s'annonce : il reçoit les événements de notre session (le fichier qu'il a lu au
-- lancement ne les contient pas encore).
local function OnPeer(sender)
	local first = math.max(1, #sessionEvents - SESSION_RESEND_MAX + 1)
	for i = first, #sessionEvents do
		if seen[sessionEvents[i]] then
			Send("E", sessionEvents[i], sender)
		end
	end
	for event, kind in pairs(withdrawn) do
		Send(kind, event, sender)
	end
end

-- RELEVÉS -----------------------------------------------------------------------------------------

-- Niveau d'objet équipé (sans décimales) : noté quand il dépasse le plus haut connu ; la première
-- lecture d'un personnage ne sert que de référence.
local ilvlPending
local function CheckItemLevel()
	ilvlPending = nil
	if not GetAverageItemLevel then
		return
	end
	local _, equipped = GetAverageItemLevel()
	local level = equipped and math.floor(equipped)
	if not level or level <= 0 then
		return
	end
	local key = P.GetCharKey()
	local previous = store.ilvl[key]
	if previous and level > previous then
		Record("ilvl", level, previous)
	end
	if not previous or level > previous then
		store.ilvl[key] = level
	end
end

-- Équipes dont le personnage joué est le leader et dont tous les membres sont dans le groupe ;
-- seul le passage à « au complet » est noté (état initial relevé sans rien noter).
local teamComplete = {}
local groupPending
local function CheckTeams(silent)
	groupPending = nil
	if not (P.GetTeams and P.GetTeamMembers and P.GetTeamLeader and P.FindGroupUnit) then
		return
	end
	local own = P.GetCharKey()
	for name in pairs(P.GetTeams()) do
		local complete, members = false, 0
		if P.GetTeamLeader(name) == own and IsInGroup() then
			complete = true
			for key in pairs(P.GetTeamMembers(name) or {}) do
				members = members + 1
				if key ~= own and not P.FindGroupUnit(key) then
					complete = false
				end
			end
			complete = complete and members > 1
		end
		if complete and not teamComplete[name] and not silent then
			Record("grp", name, members)
		end
		teamComplete[name] = complete
	end
end

local function Secret(value)
	return issecretvalue and issecretvalue(value)
end

-- Donjon : le boss vaincu est-il le dernier du Journal des donjons ? (boss facultatifs ignorés)
local function IsLastDungeonBoss(encounterID)
	if not (EJ_GetInstanceForMap and EJ_GetEncounterInfoByIndex and C_Map and C_Map.GetBestMapForUnit) then
		return false
	end
	local ok, last = pcall(function()
		local mapID = C_Map.GetBestMapForUnit("player")
		local journalID = mapID and EJ_GetInstanceForMap(mapID)
		if not journalID or journalID == 0 then
			return nil
		end
		local lastID
		local index = 1
		while true do
			local name, _, _, _, _, _, dungeonEncounterID = EJ_GetEncounterInfoByIndex(index, journalID)
			if not name then
				break
			end
			lastID = dungeonEncounterID
			index = index + 1
		end
		return lastID
	end)
	return ok and last ~= nil and last == encounterID
end

-- INSTANCES : ENTRÉE ET DURÉE -------------------------------------------------------------------

-- Instance où se trouve le personnage : identifiant « instanceID-difficulté », nom, difficulté et
-- genre (delve / party / raid), ou nil hors gouffre, donjon et raid.
local function CurrentInstance()
	local name, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
	local kind
	if difficultyID == 208 or (C_DelvesUI and C_DelvesUI.HasActiveDelve and C_DelvesUI.HasActiveDelve()) then
		kind = "delve"
	elseif instanceType == "party" or instanceType == "raid" then
		kind = instanceType
	end
	if kind and name and not Secret(name) then
		return { id = tostring(instanceID) .. "-" .. tostring(difficultyID), name = name, difficulty = difficultyID,
			kind = kind }
	end
end

-- Après un /reload dans l'instance : début et dernière fin retrouvés dans le journal (dernière
-- entrée du personnage dans cette instance, aujourd'hui ou la veille).
local function RestoreVisit(current)
	local now, key = GetServerTime(), P.GetCharKey()
	local start, last
	for _, day in ipairs({ DayOf(now - 86400), DayOf(now) }) do
		for _, event in ipairs(store.days[day] or {}) do
			local time, eventKey, kind, fields = Parse(event)
			if eventKey == key and kind == "enter" and fields[4] == current.name then
				start, last = time, nil
			elseif eventKey == key and start and COMPLETION_KINDS[kind] then
				last = time
			end
		end
	end
	current.start, current.last = start, last
	return current
end

-- À chaque PLAYER_ENTERING_WORLD : entrée notée en arrivant dans une nouvelle instance (pas au
-- /reload, pas en y revenant moins de REENTRY_DELAY après l'avoir quittée).
local function UpdateVisit(isReload)
	local current = CurrentInstance()
	if not current then
		if visit then
			left, leftAt = visit, GetServerTime()
		end
		visit = nil
		return
	end
	if visit and visit.id == current.id then
		return
	end
	if isReload then
		visit = RestoreVisit(current)
	elseif left and left.id == current.id and GetServerTime() - leftAt < REENTRY_DELAY then
		visit = left
	else
		Record("enter", current.name, current.difficulty, current.kind)
		current.start = GetServerTime()
		visit = current
	end
	left = nil
end

-- Durée depuis l'entrée ou la précédente fin dans l'instance (secondes, "" si inconnue) ; la fin
-- notée devient le départ de la suivante.
local function Elapsed()
	if not visit then
		return ""
	end
	local now, from = GetServerTime(), visit.last or visit.start
	visit.last = now
	return from and (now - from) or ""
end

local function OnEncounterEnd(encounterID, encounterName, difficultyID, _, success)
	if Secret(success) or success ~= 1 or Secret(encounterID) then
		return
	end
	local instanceName, instanceType = GetInstanceInfo()
	if Secret(encounterName) then
		encounterName = "?"
	end
	if instanceType == "raid" then
		Record("boss", encounterName, difficultyID, instanceName, Elapsed())
	elseif instanceType == "party" then
		local isChallenge = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
			and C_ChallengeMode.IsChallengeModeActive()
		if not isChallenge and IsLastDungeonBoss(encounterID) then
			Record("dng", instanceName, difficultyID, Elapsed())
		end
	end
end

local function InDelve()
	local _, _, difficultyID = GetInstanceInfo()
	return (C_DelvesUI and C_DelvesUI.HasActiveDelve and C_DelvesUI.HasActiveDelve()) or difficultyID == 208
end

-- Texte sûr (ni secret, ni vide), sinon nil.
local function SafeText(value)
	if value == nil or Secret(value) then
		return nil
	end
	value = tostring(value)
	return value ~= "" and value or nil
end

-- Palier et section du gouffre en cours. Palier : texte de l'en-tête du scénario (widget
-- ScenarioHeaderDelves de l'étape, comme Blizzard_UIWidgetTemplateScenarioHeaderDelves), sinon
-- C_DelvesUI.GetActiveDelveTier (données du groupe à l'entrée : 0 en solo). Section : titre de
-- l'étape du scénario.
local function ReadDelveState()
	local state = {}
	if C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo then
		local ok, step = pcall(C_ScenarioInfo.GetScenarioStepInfo)
		if ok and step then
			state.section = SafeText(step.title)
			local setID = step.widgetSetID
			if setID and not Secret(setID) and C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID
				and C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo then
				local okWidgets, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, setID)
				for _, widget in ipairs(okWidgets and widgets or {}) do
					if widget.widgetType == DELVES_HEADER_WIDGET then
						local okInfo, info = pcall(C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo,
							widget.widgetID)
						local tier = okInfo and info and SafeText(info.tierText)
						state.tier = tier and tier:match("%d+") or state.tier
					end
				end
			end
		end
	end
	if not state.tier and C_DelvesUI and C_DelvesUI.GetActiveDelveTier then
		local ok, info = pcall(C_DelvesUI.GetActiveDelveTier)
		local tier = ok and info and info.tier
		if tier and not Secret(tier) and tier > 0 then
			state.tier = tostring(tier)
		end
	end
	return state
end

-- Relevé gardé pendant le gouffre : à SCENARIO_COMPLETED, l'étape peut déjà être passée.
local function UpdateDelveState()
	if InDelve() then
		local state = ReadDelveState()
		delveState = { tier = state.tier or (delveState and delveState.tier), section = state.section
			or (delveState and delveState.section) }
	else
		delveState = nil
	end
end

local function OnScenarioCompleted()
	if not InDelve() then
		return
	end
	local name = GetInstanceInfo()
	local state = ReadDelveState()
	local tier = state.tier or (delveState and delveState.tier) or ""
	local section = (delveState and delveState.section) or state.section or ""
	if section == name then
		section = ""
	end
	Record("delve", name, tier, section, Elapsed())
end

local function OnChallengeCompleted()
	if not (C_ChallengeMode and C_ChallengeMode.GetChallengeCompletionInfo) then
		return
	end
	local ok, info = pcall(C_ChallengeMode.GetChallengeCompletionInfo)
	if not ok or not info or not info.mapChallengeModeID or info.mapChallengeModeID == 0 or info.practiceRun then
		return
	end
	local name = C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(info.mapChallengeModeID)
	local elapsed = Elapsed()
	local timer = info.time and not Secret(info.time) and info.time > 0 and math.floor(info.time / 1000 + 0.5)
	Record("mplus", name or info.mapChallengeModeID, info.level, info.onTime and 1 or 0,
		info.keystoneUpgradeLevels or 0, timer or elapsed)
end

-- Connexion : pas notée si le personnage s'est déconnecté il y a moins de SHORT_DELAY (sa
-- déconnexion est alors retirée : le journal le montre connecté sans interruption).
local function OnLogin()
	local now, key = GetServerTime(), P.GetCharKey()
	local last
	for _, day in ipairs({ DayOf(now), DayOf(now - SHORT_DELAY) }) do
		local list = store.days[day] or {}
		for i = #list, 1, -1 do
			local time, eventKey = Parse(list[i])
			if eventKey == key and (not last or time > last.time) then
				last = { time = time, event = list[i] }
				break
			end
		end
	end
	if last and select(3, Parse(last.event)) == "out" and now - last.time < SHORT_DELAY then
		Withdraw(last.event)
		loginEvent = nil
	else
		loginEvent, loginTime = Record("in"), now
	end
end

-- Déconnexion : rien de noté si la connexion date de moins de SHORT_DELAY (elle est retirée) ;
-- renvoie l'événement « out » noté, "short" ou "skip".
local function OnLogout()
	if loginEvent and GetServerTime() - loginTime < SHORT_DELAY then
		if not seen[loginEvent] then
			return "skip"
		end
		Withdraw(loginEvent)
		return "short"
	end
	return Record("out")
end

-- Déconnexion : notée et envoyée dès la demande (Logout / Quit, avant que le client se ferme),
-- retirée si elle est annulée (CancelLogout) ; sinon notée à PLAYER_LOGOUT (fermeture de la
-- fenêtre), sans envoi possible. /reload n'est pas une déconnexion.
local function OnLogoutRequested()
	if not loggedOut and store then
		loggedOut = OnLogout()
	end
end

local function OnLogoutCancelled()
	if loggedOut == "short" then
		-- Session courte : la connexion retirée est remise.
		withdrawn[loginEvent] = nil
		if Insert(loginEvent, true) then
			Send("E", loginEvent)
			Refresh()
		end
	elseif loggedOut and loggedOut ~= "skip" then
		Withdraw(loggedOut)
	end
	loggedOut = nil
end

-- EXPORT ------------------------------------------------------------------------------------------

-- Premier jour gardé après un export : le 1er du mois précédent.
local function KeepFrom()
	local now = date("*t")
	local year, month = now.year, now.month - 1
	if month == 0 then
		year, month = year - 1, 12
	end
	return string.format("%04d-%02d-01", year, month)
end
ns.KeepFrom = KeepFrom

-- Jours exportables (antérieurs à KeepFrom) et leur nombre d'événements.
function ns.ExportableDays()
	local cutoff, days, events = KeepFrom(), 0, 0
	for day, list in pairs(store and store.days or {}) do
		if day < cutoff then
			days = days + 1
			events = events + #list
		end
	end
	return days, events, cutoff
end

-- Ajoute les jours antérieurs à KeepFrom à l'archive (addon chargé à la demande
-- Polypode_Histoire_Archive, fichier gardé et complété), puis les retire du journal ici et chez
-- les clients connectés. Renvoie true, ou false et la raison.
function ns.Export()
	local days, events, cutoff = ns.ExportableDays()
	if days == 0 then
		return false, "rien à exporter (seuls le mois en cours et le précédent sont dans le journal)"
	end
	local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
	local ok, loaded = pcall(load, "Polypode_Histoire_Archive")
	if not ok or not loaded then
		return false, "activez « Polypode Histoire Archive » dans la liste des AddOns, puis recommencez"
	end
	PolypodeHistoireArchive = PolypodeHistoireArchive or {}
	local archive = PolypodeHistoireArchive
	archive.format = FORMAT
	archive.days = archive.days or {}
	for day, list in pairs(store.days) do
		if day < cutoff then
			local target = archive.days[day] or {}
			local known = {}
			for _, event in ipairs(target) do
				known[event] = true
			end
			for _, event in ipairs(list) do
				if not known[event] then
					target[#target + 1] = event
				end
			end
			table.sort(target, function(a, b)
				return (tonumber((strsplit(SEP, a))) or 0) < (tonumber((strsplit(SEP, b))) or 0)
			end)
			archive.days[day] = target
		end
	end
	archive.updated = GetServerTime()
	ApplyCutoff(cutoff)
	Send("P", cutoff)
	return true, events
end

-- ÉVÉNEMENTS ----------------------------------------------------------------------------------------

if P.RegisterMessageHandler then
	P.RegisterMessageHandler(MESSAGE_TYPE, OnMessage)
	P.RegisterPeerCallback(OnPeer)
end

for _, name in ipairs({ "Logout", "Quit", "ForceQuit" }) do
	if type(_G[name]) == "function" then
		hooksecurefunc(name, OnLogoutRequested)
	end
end
if type(CancelLogout) == "function" then
	hooksecurefunc("CancelLogout", OnLogoutCancelled)
end
if type(ReloadUI) == "function" then
	hooksecurefunc("ReloadUI", function()
		reloading = true
	end)
end
if C_UI and type(C_UI.Reload) == "function" then
	hooksecurefunc(C_UI, "Reload", function()
		reloading = true
	end)
end

-- COLLECTIONS ET RÉPUTATIONS --------------------------------------------------------------------

-- Collections (jouets, montures, mascottes) : un nom lu au moment du relevé, gardé dans l'événement.
local function OnToyAdded(itemID)
	local name
	if C_ToyBox and C_ToyBox.GetToyInfo then
		name = select(2, C_ToyBox.GetToyInfo(itemID))
	end
	name = name or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID))
	Record("toy", itemID, name or "")
end

local function OnMountAdded(mountID)
	local name = C_MountJournal and C_MountJournal.GetMountInfoByID and C_MountJournal.GetMountInfoByID(mountID)
	Record("mount", mountID, name or "")
end

local function OnPetAdded(petGUID)
	if not (C_PetJournal and C_PetJournal.GetPetInfoByPetID) then
		return
	end
	local ok, speciesID, _, _, _, _, _, _, name = pcall(C_PetJournal.GetPetInfoByPetID, petGUID)
	if ok and speciesID then
		Record("pet", speciesID, name or "")
	end
end

local function OnRenownChanged(factionID, newLevel, oldLevel)
	if Secret(newLevel) or not newLevel or (oldLevel and newLevel <= oldLevel) then
		return
	end
	local data = C_MajorFactions and C_MajorFactions.GetMajorFactionData and C_MajorFactions.GetMajorFactionData(factionID)
	-- Renom sans nom : compteur technique caché (ex. 2739 « Gouffres : conversion de fragments de clé
	-- de coffre ») : pas noté.
	if not data or not data.name or Secret(data.name) or data.name == "" then
		return
	end
	Record("renown", factionID, newLevel, data.name)
end

-- Rang d'une réputation (hors factions majeures, suivies par leur renom) : numéro et texte, ou nil.
-- Amitié : rang de C_GossipInfo ; sinon reaction 1..8 (FACTION_STANDING_LABEL<n>).
local function ReputationRank(factionID)
	if C_Reputation and C_Reputation.IsMajorFaction and C_Reputation.IsMajorFaction(factionID) then
		return nil
	end
	local data = C_Reputation and C_Reputation.GetFactionDataByID and C_Reputation.GetFactionDataByID(factionID)
	if not data or data.isHeader and not data.isHeaderWithRep then
		return nil
	end
	if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
		local friendship = C_GossipInfo.GetFriendshipReputation(factionID)
		if friendship and friendship.friendshipFactionID and friendship.friendshipFactionID > 0 then
			local ranks = C_GossipInfo.GetFriendshipReputationRanks and C_GossipInfo.GetFriendshipReputationRanks(factionID)
			return ranks and ranks.currentLevel, friendship.reaction, data.name
		end
	end
	return data.reaction, data.reaction and _G["FACTION_STANDING_LABEL" .. data.reaction], data.name
end

-- Rangs connus du personnage joué : PolypodeHistoireChar.rep[factionID] (fichier propre au
-- personnage, écrit par son seul client). Première lecture d'une faction = référence, rien de noté.
local function OnFactionStandingChanged(factionID)
	if not factionID or Secret(factionID) then
		return
	end
	local ok, level, rank, name = pcall(ReputationRank, factionID)
	if not ok or not level or Secret(level) then
		return
	end
	PolypodeHistoireChar = PolypodeHistoireChar or {}
	PolypodeHistoireChar.rep = PolypodeHistoireChar.rep or {}
	local known = PolypodeHistoireChar.rep[factionID]
	PolypodeHistoireChar.rep[factionID] = math.max(known or 0, level)
	if known and level > known then
		Record("rep", factionID, rank or level, name or "", level)
	end
end

-- À la connexion : rangs de référence des factions visibles dans le panneau Réputation (celles
-- des en-têtes repliés le seront à leur premier changement).
local function SeedReputations()
	if not (C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex) then
		return
	end
	PolypodeHistoireChar = PolypodeHistoireChar or {}
	PolypodeHistoireChar.rep = PolypodeHistoireChar.rep or {}
	for i = 1, C_Reputation.GetNumFactions() do
		local data = C_Reputation.GetFactionDataByIndex(i)
		local factionID = data and data.factionID
		if factionID and not Secret(factionID) and not PolypodeHistoireChar.rep[factionID] then
			local ok, level = pcall(ReputationRank, factionID)
			if ok and level and not Secret(level) then
				PolypodeHistoireChar.rep[factionID] = level
			end
		end
	end
end

-- SOCIAL ------------------------------------------------------------------------------------------

-- Amis, guilde et communautés du personnage joué, comparés à ceux gardés dans PolypodeHistoireChar
-- (friends, bnet, guild, clubs) : chaque écart est noté. Rien n'est comparé avant SOCIAL_DELAY
-- après la connexion (listes encore incomplètes) ; un premier relevé sans référence n'en sert que.
local SOCIAL_DELAY = 10
local socialReady, socialPending

local function CharStore()
	PolypodeHistoireChar = PolypodeHistoireChar or {}
	return PolypodeHistoireChar
end

-- Ensembles { [nom] = true } (nil si la liste n'est pas lisible) ; clubs : { [id] = { name, b } }.
local function ReadFriends()
	if not (C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex) then
		return nil
	end
	local set = {}
	for i = 1, C_FriendList.GetNumFriends() or 0 do
		local info = C_FriendList.GetFriendInfoByIndex(i)
		local name = info and info.name
		if name and not Secret(name) and name ~= "" then
			set[name] = true
		end
	end
	return set
end

local function ReadBNetFriends()
	if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then
		return nil
	end
	local set = {}
	for i = 1, (BNGetNumFriends()) or 0 do
		local info = C_BattleNet.GetFriendAccountInfo(i)
		local tag = info and info.battleTag
		if tag and not Secret(tag) and tag ~= "" then
			set[(tag:gsub("#%d+$", ""))] = true
		end
	end
	return set
end

local function ReadGuild()
	if not IsInGuild then
		return nil
	end
	if not IsInGuild() then
		return ""
	end
	local name = GetGuildInfo("player")
	if name and not Secret(name) then
		return name
	end
	return nil -- dans une guilde dont le nom n'est pas encore connu
end

local function ReadClubs()
	if not (C_Club and C_Club.GetSubscribedClubs) then
		return nil
	end
	local guildType = Enum and Enum.ClubType and Enum.ClubType.Guild or 2
	local bnetType = Enum and Enum.ClubType and Enum.ClubType.BattleNet or 0
	local clubs = {}
	for _, info in ipairs(C_Club.GetSubscribedClubs() or {}) do
		if info.clubId and info.clubType ~= guildType and info.name and not Secret(info.name) then
			clubs[tostring(info.clubId)] = { name = info.name, b = info.clubType == bnetType }
		end
	end
	return clubs
end

-- Écarts entre deux ensembles : ajoutés (+) puis retirés (-).
local function DiffSets(old, new, record)
	for name in pairs(new) do
		if not old[name] then
			record(name, "+")
		end
	end
	for name in pairs(old) do
		if not new[name] then
			record(name, "-")
		end
	end
end

-- Liste vide alors que la référence ne l'était pas : sans doute pas encore chargée, on attend
-- (retirer d'un coup tous ses amis ou toutes ses communautés n'est donc pas noté).
local function Usable(new, old)
	return new and not (next(new) == nil and old and next(old) ~= nil)
end

local function CheckSocial()
	socialPending = nil
	if not socialReady or not store then
		return
	end
	local char = CharStore()
	local friends = ReadFriends()
	if Usable(friends, char.friends) then
		if char.friends then
			DiffSets(char.friends, friends, function(name, sign)
				Record("friend", name, sign, "c")
			end)
		end
		char.friends = friends
	end
	local bnet = ReadBNetFriends()
	if Usable(bnet, char.bnet) then
		if char.bnet then
			DiffSets(char.bnet, bnet, function(name, sign)
				Record("friend", name, sign, "b")
			end)
		end
		char.bnet = bnet
	end
	local guild = ReadGuild()
	if guild then
		if char.guild and char.guild ~= guild then
			if char.guild ~= "" then
				Record("guild", char.guild, "-")
			end
			if guild ~= "" then
				Record("guild", guild, "+")
			end
		end
		char.guild = guild
	end
	local clubs = ReadClubs()
	if Usable(clubs, char.clubs) then
		if char.clubs then
			for id, club in pairs(clubs) do
				if not char.clubs[id] then
					Record("club", club.name, "+", club.b and "b" or "c")
				end
			end
			for id, club in pairs(char.clubs) do
				if not clubs[id] then
					Record("club", club.name, "-", club.b and "b" or "c")
				end
			end
		end
		char.clubs = clubs
	end
end

local function ScheduleSocial()
	if socialReady and not socialPending then
		socialPending = true
		C_Timer.After(2, CheckSocial)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LOGOUT")
for _, event in ipairs({ "PLAYER_LEVEL_UP", "ACHIEVEMENT_EARNED", "PLAYER_EQUIPMENT_CHANGED",
	"PLAYER_AVG_ITEM_LEVEL_UPDATE", "GROUP_ROSTER_UPDATE", "ENCOUNTER_END", "SCENARIO_COMPLETED",
	"CHALLENGE_MODE_COMPLETED", "SCENARIO_UPDATE", "SCENARIO_CRITERIA_UPDATE", "NEW_TOY_ADDED", "NEW_MOUNT_ADDED",
	"NEW_PET_ADDED", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "FACTION_STANDING_CHANGED", "FRIENDLIST_UPDATE",
	"BN_FRIEND_LIST_SIZE_CHANGED", "PLAYER_GUILD_UPDATE", "CLUB_ADDED", "CLUB_REMOVED" }) do
	if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(event) then
		events:RegisterEvent(event)
	end
end
events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if ... == "Polypode_Histoire" then
			PolypodeHistoireData = PolypodeHistoireData or {}
			store = PolypodeHistoireData
			store.format = FORMAT
			store.days = store.days or {}
			store.ilvl = store.ilvl or {}
			store.deleted = store.deleted or {}
			-- Traces de retrait trop anciennes (ou illisibles) oubliées.
			local oldest = GetServerTime() - DELETED_KEEP
			for text, mark in pairs(store.deleted) do
				local at = type(mark) == "string" and tonumber(mark:match("^[DR]:(%d+)$"))
				if not at or at < oldest then
					store.deleted[text] = nil
				end
			end
			Reindex()
		end
		return
	end
	if not store then
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		local isLogin, isReload = ...
		if isLogin then
			OnLogin()
			C_Timer.After(5, SeedReputations)
			C_Timer.After(SOCIAL_DELAY, function()
				socialReady = true
				CheckSocial()
			end)
			if size >= ns.WARN_SIZE then
				C_Timer.After(10, function()
					UIErrorsFrame:AddMessage(string.format("Polypode Histoire : journal de %.1f Mo, pensez à "
						.. "l'exporter (/poly histoire).", size / 1048576), 1, 0.5, 0)
				end)
			end
		end
		CheckTeams(true)
		C_Timer.After(ILVL_DELAY, CheckItemLevel)
		UpdateDelveState()
		UpdateVisit(isReload)
	elseif event == "PLAYER_LOGOUT" then
		if not reloading and not loggedOut then
			OnLogout()
		end
	elseif event == "PLAYER_LEVEL_UP" then
		Record("lvl", (...))
	elseif event == "ACHIEVEMENT_EARNED" then
		local achievementID, alreadyEarned = ...
		if achievementID and not alreadyEarned then
			Record("ach", achievementID)
		end
	elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_AVG_ITEM_LEVEL_UPDATE" then
		if not ilvlPending then
			ilvlPending = true
			C_Timer.After(ILVL_DELAY, CheckItemLevel)
		end
	elseif event == "GROUP_ROSTER_UPDATE" then
		if not groupPending then
			groupPending = true
			C_Timer.After(GROUP_MERGE_DELAY, function()
				CheckTeams(false)
			end)
		end
	elseif event == "ENCOUNTER_END" then
		OnEncounterEnd(...)
	elseif event == "SCENARIO_COMPLETED" then
		OnScenarioCompleted()
	elseif event == "SCENARIO_UPDATE" or event == "SCENARIO_CRITERIA_UPDATE" then
		UpdateDelveState()
	elseif event == "NEW_TOY_ADDED" then
		OnToyAdded(...)
	elseif event == "NEW_MOUNT_ADDED" then
		OnMountAdded(...)
	elseif event == "NEW_PET_ADDED" then
		OnPetAdded(...)
	elseif event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" then
		OnRenownChanged(...)
	elseif event == "FACTION_STANDING_CHANGED" then
		OnFactionStandingChanged(...)
	elseif event == "FRIENDLIST_UPDATE" or event == "BN_FRIEND_LIST_SIZE_CHANGED" or event == "PLAYER_GUILD_UPDATE"
		or event == "CLUB_ADDED" or event == "CLUB_REMOVED" then
		ScheduleSocial()
	elseif event == "CHALLENGE_MODE_COMPLETED" then
		OnChallengeCompleted()
	end
end)
