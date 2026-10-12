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
--   delve nom~palier  gouffre terminé
--   dng  nom~difficulté  donjon terminé (dernier boss du Journal des donjons vaincu, hors clé M+)
--   mplus nom~niveau~àTemps(1/0)~améliorations  clé mythique+ terminée
--   boss nom~difficulté~raid  boss de raid vaincu
-- Messages : HIST:token:E:<événement> (nouvel événement), HIST:token:R:<événement> (retrait :
-- déconnexion annulée), HIST:token:P:<AAAA-MM-JJ> (export : jours antérieurs retirés).

local MESSAGE_TYPE = "HIST"
local SEP = "~"
local FORMAT = 1
local LINE_OVERHEAD = 16 -- octets par événement dans le fichier en plus du texte (« "...", -- [n] »)
local DAY_OVERHEAD = 30 -- octets par jour (clé et accolades)
ns.WARN_SIZE = 2 * 1024 * 1024 -- avertissement : export conseillé
ns.ALERT_SIZE = 5 * 1024 * 1024 -- alerte (rouge)
local SESSION_RESEND_MAX = 100 -- événements de la session renvoyés à un client qui s'annonce
local GROUP_MERGE_DELAY = 2 -- secondes : regroupe les GROUP_ROSTER_UPDATE rapprochés
local ILVL_DELAY = 3 -- secondes : regroupe les changements d'équipement
local SHORT_DELAY = 180 -- secondes : déco-reco ou session plus courtes ne sont pas notées

local store -- = PolypodeHistoireData : { format, days = { [jour] = { événements } }, ilvl = { [clé] = n }, cutoff }
local seen = {} -- [événement] = true, index des doublons (construit au chargement)
local sessionEvents = {} -- événements du personnage joué pendant la session (renvoyés aux clients qui s'annoncent)
local size = 0 -- taille estimée du journal dans le fichier (octets)
local count = 0 -- nombre d'événements
local withdrawn = {} -- [événement] = true, retirés pendant la session (retrait renvoyé aux clients qui s'annoncent)
local reloading -- /reload en cours : PLAYER_LOGOUT n'est pas une déconnexion
local loginEvent, loginTime -- événement « in » de la session (nil si reconnexion rapide) et son heure
local loggedOut -- déconnexion traitée par Logout / Quit (annulée par CancelLogout) : événement « out »
-- noté, ou "short" si la session était trop courte (connexion retirée, rien de noté)

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

-- Ajoute un événement à son jour (trié par heure) ; faux si doublon, mal formé ou antérieur au
-- dernier export.
local function Insert(event)
	if seen[event] then
		return false
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

-- Retire un événement du personnage joué, ici et chez les clients connectés (renvoyé à ceux qui
-- s'annoncent ensuite).
local function Withdraw(event)
	Remove(event)
	withdrawn[event] = true
	Send("R", event)
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
	-- Événement : seulement celui du personnage qui l'envoie.
	local _, key = Parse(payload)
	if not key or not (P.IsSender and P.IsSender(sender, key)) then
		return
	end
	if kind == "E" then
		if Insert(payload) then
			Refresh()
		end
	elseif kind == "R" then
		Remove(payload)
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
	for event in pairs(withdrawn) do
		Send("R", event, sender)
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

local function OnEncounterEnd(encounterID, encounterName, difficultyID, _, success)
	if Secret(success) or success ~= 1 or Secret(encounterID) then
		return
	end
	local instanceName, instanceType = GetInstanceInfo()
	if Secret(encounterName) then
		encounterName = "?"
	end
	if instanceType == "raid" then
		Record("boss", encounterName, difficultyID, instanceName)
	elseif instanceType == "party" then
		local isChallenge = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
			and C_ChallengeMode.IsChallengeModeActive()
		if not isChallenge and IsLastDungeonBoss(encounterID) then
			Record("dng", instanceName, difficultyID)
		end
	end
end

local function OnScenarioCompleted()
	local name, _, difficultyID = GetInstanceInfo()
	local isDelve = (C_DelvesUI and C_DelvesUI.HasActiveDelve and C_DelvesUI.HasActiveDelve()) or difficultyID == 208
	if not isDelve then
		return
	end
	local tier = ""
	if C_DelvesUI and C_DelvesUI.GetActiveDelveTier then
		local ok, info = pcall(C_DelvesUI.GetActiveDelveTier)
		tier = ok and info and info.tier or ""
	end
	Record("delve", name, tier)
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
	Record("mplus", name or info.mapChallengeModeID, info.level, info.onTime and 1 or 0,
		info.keystoneUpgradeLevels or 0)
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
-- renvoie l'événement « out » noté, ou "short".
local function OnLogout()
	if loginEvent and GetServerTime() - loginTime < SHORT_DELAY then
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
		if Insert(loginEvent) then
			Send("E", loginEvent)
			Refresh()
		end
	elseif loggedOut then
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

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LOGOUT")
for _, event in ipairs({ "PLAYER_LEVEL_UP", "ACHIEVEMENT_EARNED", "PLAYER_EQUIPMENT_CHANGED",
	"PLAYER_AVG_ITEM_LEVEL_UPDATE", "GROUP_ROSTER_UPDATE", "ENCOUNTER_END", "SCENARIO_COMPLETED",
	"CHALLENGE_MODE_COMPLETED" }) do
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
			Reindex()
		end
		return
	end
	if not store then
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		local isLogin = ...
		if isLogin then
			OnLogin()
			if size >= ns.WARN_SIZE then
				C_Timer.After(10, function()
					UIErrorsFrame:AddMessage(string.format("Polypode Histoire : journal de %.1f Mo, pensez à "
						.. "l'exporter (/poly histoire).", size / 1048576), 1, 0.5, 0)
				end)
			end
		end
		CheckTeams(true)
		C_Timer.After(ILVL_DELAY, CheckItemLevel)
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
	elseif event == "CHALLENGE_MODE_COMPLETED" then
		OnChallengeCompleted()
	end
end)
