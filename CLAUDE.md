# CLAUDE.md — Polypode Histoire (Addon WoW)

Conventions communes et procédure de documentation de tous les modules Polypode (chargées
automatiquement, quel que soit le dossier ouvert) :

@../Polypode/MODULES.md

Addon compagnon de **Polypode** (dossier voisin `../Polypode`, dépôt séparé) : **journal
chronologique commun** des événements importants de tous les personnages joués. Rester **simple** :
on n'ajoute un type d'événement que s'il raconte l'histoire des personnages, sans détail superflu.

## Architecture

| Fichier | Rôle |
|---|---|
| `Polypode_Histoire.toc` | `## Dependencies: Polypode`, SavedVariables de compte `PolypodeHistoireData` (le journal) et `PolypodeHistoireDB` (fenêtre : `open` repli, `width` / `height`) |
| `Journal.lua` | Relevé, stockage, synchro, export. Événement = texte `heure~nom-royaume~type~champs...` (`GetServerTime`, champs nettoyés par `Clean` : ni `~`, ni `\|`, ni saut de ligne), rangé dans `store.days["AAAA-MM-JJ"]` (jour local, `DayOf`) trié par heure (`Insert`, doublons par l'index `seen` ; refusé si antérieur à `store.cutoff`). `Record(type, ...)` : événement du personnage joué, ajouté puis envoyé (`Send("E")`) et gardé dans `sessionEvents`. Types : `in` (`PLAYER_ENTERING_WORLD` isLogin), `out` (accroches `Logout` / `Quit` / `ForceQuit`, retiré par `CancelLogout` → `Send("R")` ; sinon à `PLAYER_LOGOUT` hors `/reload` — accroches `ReloadUI` / `C_UI.Reload`), `grp` équipe~membres (`CheckTeams` 2 s après `GROUP_ROSTER_UPDATE` : équipes dont le joueur est leader, tous les membres trouvés par `P.FindGroupUnit` ; seul le passage à « au complet » est noté, état initial relevé en silence à chaque `PLAYER_ENTERING_WORLD`), `lvl` (`PLAYER_LEVEL_UP`), `ach` id (`ACHIEVEMENT_EARNED`, pas si `alreadyEarned`), `ilvl` nouveau~ancien (`CheckItemLevel` 3 s après `PLAYER_EQUIPMENT_CHANGED` / `PLAYER_AVG_ITEM_LEVEL_UPDATE` : `GetAverageItemLevel` équipé arrondi par défaut, noté s'il dépasse `store.ilvl[clé]`, première lecture = référence), `delve` nom~palier (`SCENARIO_COMPLETED` dans un gouffre : `C_DelvesUI.HasActiveDelve` ou difficulté 208 ; palier `C_DelvesUI.GetActiveDelveTier().tier`), `dng` nom~difficulté (`ENCOUNTER_END` réussi en instance « party » hors clé, si le boss est le dernier du Journal des donjons : `IsLastDungeonBoss`, `EJ_GetInstanceForMap` + `EJ_GetEncounterInfoByIndex` 7e retour), `mplus` nom~niveau~àTemps~améliorations (`CHALLENGE_MODE_COMPLETED` → `C_ChallengeMode.GetChallengeCompletionInfo`, pas les `practiceRun`), `boss` nom~difficulté~raid (`ENCOUNTER_END` réussi en raid ; valeurs secrètes écartées par `issecretvalue`). Synchro : `HIST:token:E:<événement>` (ajout), `R` (retrait), `P:<AAAA-MM-JJ>` (purge après export → `ApplyCutoff`) ; un événement reçu n'est accepté que de son personnage (`P.IsSender`) ; à chaque HELLO/HI (`OnPeer`), les `SESSION_RESEND_MAX` derniers `sessionEvents` sont renvoyés. Taille estimée `size` (texte + `LINE_OVERHEAD` par événement + `DAY_OVERHEAD` par jour, `Reindex`) ; seuils `ns.WARN_SIZE` 2 Mo (message 10 s après la connexion) et `ns.ALERT_SIZE` 5 Mo. Export `ns.Export` : jours antérieurs à `KeepFrom()` (1er du mois précédent) fusionnés sans doublon dans `PolypodeHistoireArchive.days` après `C_AddOns.LoadAddOn("Polypode_Histoire_Archive")`, puis `ApplyCutoff` et `Send("P")` |
| `Histoire.lua` | Fenêtre `PolypodeHistoireFrame` (`P.ToggleHistoire`, `ns.Refresh` = `P.RefreshHistoire`, `P.ui.histoireFrame`), redimensionnable : `BuildItems` → en-têtes `{ header = 1..3 (année, mois, jour), key, label, count }` du plus récent au plus ancien, dépliés selon `IsOpen` (`PolypodeHistoireDB.open[clé]`, sinon déplié pour la période en cours) ; lignes d'un jour par `DayLines` (même type et mêmes champs, personnages différents, moins de `MERGE_WINDOW` = 300 s d'écart → une ligne, sauf `grp`), texte `EventText` (noms à la couleur de classe, verbe au pluriel, noms de hauts faits et de difficultés lus au moment de l'affichage), infobulle `ItemTooltip` (heure de chaque personnage). En-tête `HeaderText` (événements, taille, couleur selon les seuils), boutons « Tout replier » / « Tout déplier » et « Exporter » (`AskExport` → popup `POLYPODE_HISTOIRE_EXPORT`). Bouton `P.AddTitleButton` « Histoire » (`P.ui.histoireButton`), commande `/poly histoire` |
| `Polypode_Histoire_Archive/` | Addon **chargé à la demande** (`## LoadOnDemand: 1`, dépend de Polypode_Histoire), SavedVariables `PolypodeHistoireArchive` (`format`, `updated`, `days` au même format que le journal) : jamais lu au lancement, donc jamais réécrit par les autres clients ; relié au jeu par sa **propre jonction** (`Interface\AddOns\Polypode_Histoire_Archive` → ce sous-dossier ; WoW ne lit pas les dossiers imbriqués) |

**Fichier partagé** : les comptes de multibox partagent le dossier `SavedVariables` (jonctions de
`WTF\Account`) ; le dernier client qui quitte écrit `Polypode_Histoire.lua`. D'où la synchro de
chaque événement, le renvoi de la session aux clients qui arrivent, et la purge diffusée à l'export.

## Dépendances vers Polypode (API publique utilisée)

`P.AddTitleButton`, `P.RegisterSlashCommand`, `P.RegisterMessageHandler`, `P.RegisterPeerCallback`,
`P.WhisperOnline`, `P.IsSender`, `P.MAX_MESSAGE_LENGTH`, `P.GetTeamToken`, `P.GetCharKey`,
`P.GetDisplayName`, `P.db.roster`, `P.GetTeams`, `P.GetTeamMembers`, `P.GetTeamLeader`,
`P.FindGroupUnit`, `P.CreatePanel`, `P.CreateScrollList`, `P.SetListData`, `P.SkinFrame`,
`P.SkinPanel`, `P.SkinButton`, `P.ShowTooltip`, `P.ui`. Toute évolution de ces fonctions dans
Polypode doit rester compatible, ou ce fichier doit suivre.

## Pistes

- Détail dépliable d'un événement (butin d'un gouffre ou d'un donjon) : à vérifier d'abord, les
  messages de butin pouvant être des valeurs secrètes en instance sur Midnight.
- Logiciel tiers lisant `Polypode_Histoire_Archive.lua` (conversion JSON / CSV, publication).

## Après chaque modification

Appliquer la procédure de `../Polypode/MODULES.md` (« Après chaque modification d'un module »),
sans attendre qu'on le demande : version du `.toc` et du commit, ligne en tête de la section
« Version » du `README.md` et sections d'utilisation, ce fichier (architecture, dépendances),
Polypode si le périmètre change, puis commit et push sur `origin` (https://github.com/Baktov/polypode-histoire).
