-- Polypode Histoire: Donjons — boss obligatoires des donjons de WoW Forever
-- Un donjon de WoW Forever est noté terminé quand tous ses boss obligatoires ont été tués pendant
-- la visite, dans n'importe quel ordre (Journal.lua, OnEncounterEnd). Chaque boss = liste de ses
-- numéros de combat (encounterID d'ENCOUNTER_END : un même boss peut en avoir plusieurs, les boss
-- repris plus tard ayant reçu de nouveaux numéros). Écartés : boss rares, facultatifs, invoqués ou
-- liés à une quête, boss sans numéro de combat connu (pas d'ENCOUNTER_END à attendre), et boss qui
-- n'ont qu'un ancien numéro quand les autres boss du donjon en ont un récent (Lorgus Jett, Solakar
-- Flamewreath : plus des combats sur Forever).
-- Source : données de l'addon DungeonJournal (ForeverDungeonJournal 2.0.9 : Data/Dungeons.lua et
-- Data/RunLogEncounters.lua, tirées de DungeonEncounter.db2 de Forever 1.60.1), relevées le
-- 2026-11-17. Clé = nom anglais du donjon (lisibilité seulement : la recherche se fait par numéro).
local _, ns = ...

ns.FOREVER_DUNGEONS = {
	["Alcaz Prison"] = {
		{ 3403 }, -- Overseer Wrex
		{ 3415 }, -- The Questioner
		{ 3410 }, -- Tidemistress Ca'zass
		{ 3418 }, -- Katerina the Cleaner
		{ 3409 }, -- Blazeroar
	},
	["Blackfathom Deeps"] = {
		{ 219, 2761, 2916 }, -- Ghamoo-ra
		{ 220, 2762, 2915 }, -- Lady Sarevess
		{ 221, 2763, 2914 }, -- Gelihast
		{ 224, 2765, 2912 }, -- Old Serra'kis
		{ 225, 2766, 2911 }, -- Twilight Lord Kelris
		{ 226, 2767, 2910 }, -- Aku'mai
	},
	["Blackmaw Hold"] = {
		{ 3316 }, -- Impaan the Imprisoner
		{ 3322 }, -- Bonesnout the Unbroken
		{ 3315 }, -- Withermaw
		{ 3327 }, -- Elder Shaman Bloodmane
		{ 3323 }, -- Blackmaw Behemoth
		{ 3336 }, -- Unbound Spirit
		{ 3334 }, -- Varrox Bleakhoof
	},
	["Blackrock Depths"] = {
		{ 227 }, -- High Interrogator Gerstahn
		{ 228 }, -- Lord Roccor
		{ 229 }, -- Houndmaster Grebmar
		{ 230 }, -- Ring of Law
		{ 231 }, -- Pyromancer Loregrain
		{ 234 }, -- Fineous Darkvire
		{ 233 }, -- Warder Stilgiss
		{ 232 }, -- Lord Incendius
		{ 235 }, -- Bael'Gar
		{ 236 }, -- General Angerforge
		{ 237 }, -- Golem Lord Argelmach
		{ 238 }, -- Hurley Blackbreath
		{ 239 }, -- Phalanx
		{ 240 }, -- Ribbly Screwspigot
		{ 241 }, -- Plugger Spazzring
		{ 242 }, -- Ambassador Flamelash
		{ 243 }, -- The Seven
		{ 244 }, -- Magmus
		{ 245 }, -- Emperor Dagran Thaurissan
	},
	["City of Dalaran"] = {
		{ 3311 }, -- Atrexis the Grave Knight
		{ 3298 }, -- Arcane Anomaly
		{ 3299 }, -- Fel Ancient
		{ 3302 }, -- Unstable Sentinel
		{ 3300 }, -- Mana Devourer
		{ 3303 }, -- Shade of the Archmage
	},
	["Dire Maul: East"] = {
		{ 343 }, -- Zevrim Thornhoof
		{ 344 }, -- Hydrospawn
		{ 345 }, -- Lethtendris
		{ 346 }, -- Alzzin the Wildshaper
	},
	["Dire Maul: North"] = {
		{ 362 }, -- Guard Mol'dar
		{ 363 }, -- Stomper Kreeg
		{ 364 }, -- Guard Fengus
		{ 365 }, -- Guard Slip'kik
		{ 366 }, -- Captain Kromcrush
		{ 367 }, -- Cho'Rush the Observer
		{ 368 }, -- King Gordok
	},
	["Dire Maul: West"] = {
		{ 350 }, -- Tendris Warpwood
		{ 348 }, -- Magister Kalendris
		{ 347 }, -- Illyanna Ravenoak
		{ 349 }, -- Immol'thar
		{ 361 }, -- Prince Tortheldrin
	},
	["Excavation Site: Wetlands"] = {
		{ 3480 }, -- Saltspine
		{ 3481 }, -- Shadetooth
		{ 3482 }, -- Relic Guardian
	},
	["Gnomeregan"] = {
		{ 379 }, -- Grubbis
		{ 378 }, -- Viscous Fallout
		{ 380 }, -- Electrocutioner 6000
		{ 381 }, -- Crowd Pummeler 9-60
		{ 382 }, -- Mekgineer Thermaplugg
	},
	["Hall of Thanes"] = {
		{ 3493 }, -- Faldrim Anvilmar
		{ 3494 }, -- Plunder
		{ 3496 }, -- Durgen Dirgehammer
	},
	["Krol'dok Stronghold"] = {
		{ 3450 }, -- Slavecrusher Grox
		{ 3452 }, -- Twilight Commander Zarmok
		{ 3453 }, -- War Handler Ashka
		{ 3449 }, -- Nar'gurk
		{ 3451 }, -- Overlord Mugg
	},
	["Lower Blackrock Spire"] = {
		{ 267 }, -- Highlord Omokk
		{ 268 }, -- Shadow Hunter Vosh'gajin
		{ 269 }, -- War Master Voone
		{ 270 }, -- Mother Smolderweb
		{ 271 }, -- Urok Doomhowl
		{ 272 }, -- Quartermaster Zigris
		{ 274 }, -- Halycon
		{ 273 }, -- Gizrul the Slavener
		{ 275 }, -- Overlord Wyrmthalak
	},
	["Maraudon"] = {
		{ 422 }, -- Noxxion
		{ 423 }, -- Razorlash
		{ 424 }, -- Lord Vyletongue
		{ 425 }, -- Celebras the Cursed
		{ 426 }, -- Landslide
		{ 427 }, -- Tinkerer Gizlock
		{ 428 }, -- Rotgrip
		{ 429 }, -- Princess Theradras
	},
	["Ragefire Chasm"] = {
		{ 430, 2732 }, -- Oggleflint
		{ 431, 2733 }, -- Taragaman the Hungerer
		{ 432, 2734 }, -- Jergosh the Invoker
		{ 433, 2735 }, -- Bazzalan
	},
	["Razorfen Downs"] = {
		{ 434, 2780 }, -- Tuten'kash
		{ 435, 2782 }, -- Mordresh Fire Eye
		{ 436, 2784 }, -- Glutton
		{ 437, 2785 }, -- Amnennar the Coldbringer
	},
	["Razorfen Kraul"] = {
		{ 2773 }, -- Roogug
		{ 439, 2774 }, -- Aggem Thorncurse
		{ 440, 2775 }, -- Death Speaker Jargba
		{ 441, 2776 }, -- Overlord Ramtusk
		{ 883, 2777 }, -- Agathelos the Raging
		{ 443, 2778 }, -- Charlga Razorflank
	},
	["Ruins of Lordaeron"] = {
		{ 3353 }, -- Witherfang
		{ 3411 }, -- Viktor the Vile
		{ 3357 }, -- The Abandoned
		{ 3412 }, -- Bjork
		{ 3354 }, -- Rath'mael
	},
	["Scarlet Monastery: Armory"] = {
		{ 448 }, -- Herod
	},
	["Scarlet Monastery: Cathedral"] = {
		{ 449 }, -- High Inquisitor Fairbanks
		{ 450 }, -- High Inquisitor Whitemane
	},
	["Scarlet Monastery: Graveyard"] = {
		{ 444 }, -- Interrogator Vishas
		{ 445 }, -- Bloodmage Thalnos
	},
	["Scarlet Monastery: Library"] = {
		{ 446 }, -- Houndmaster Loksey
		{ 447 }, -- Arcanist Doan
	},
	["Shadowfang Keep"] = {
		{ 464, 2748 }, -- Rethilgore
		{ 465, 2749 }, -- Razorclaw the Butcher
		{ 466, 2750 }, -- Baron Silverlaine
		{ 467, 2751 }, -- Commander Springvale
		{ 468, 2752 }, -- Odo the Blindwatcher
		{ 469, 2753 }, -- Fenrus the Devourer
		{ 470, 2754 }, -- Wolf Master Nandos
		{ 471, 2755 }, -- Archmage Arugal
	},
	["Shaper's Terrace"] = {
		{ 3498 }, -- Titanosaur
		{ 3501 }, -- Venomridge
		{ 3500 }, -- Thunderhoof
		{ 3507 }, -- Direhorn Matriarch
		{ 3503 }, -- Cinder
		{ 3505 }, -- Bolt
		{ 3597 }, -- Snowtalon
		{ 3600 }, -- Vitrix
		{ 3502 }, -- Nanaya
	},
	["Stratholme: Living"] = {
		{ 472 }, -- The Unforgiven
		{ 474 }, -- Timmy the Cruel
		{ 475 }, -- Cannon Master Willey
		{ 477 }, -- Archivist Galford
		{ 478 }, -- Balnazzar
	},
	["Stratholme: Undead"] = {
		{ 480 }, -- Nerub'enkan
		{ 479 }, -- Baroness Anastari
		{ 481 }, -- Maleki the Pallid
		{ 482 }, -- Magistrate Barthilas
		{ 483 }, -- Ramstein the Gorger
		{ 484 }, -- Baron Rivendare
	},
	["Sunken Temple"] = {
		{ 490, 491 }, -- Morphaz & Hazzas
		{ 488 }, -- Jammal'an the Prophet
		{ 486, 487 }, -- Dreamscythe & Weaver
		{ 493 }, -- Shade of Eranikus
		{ 492 }, -- Avatar of Hakkar
	},
	["The Deadmines"] = {
		{ 161, 2741 }, -- Rhahk'Zor
		{ 162, 2742 }, -- Sneed
		{ 163, 2743 }, -- Gilnid
		{ 164, 2745 }, -- Mr. Smite
		{ 166, 2744 }, -- Captain Greenskin
		{ 167, 2747 }, -- Edwin VanCleef
		{ 165, 2746 }, -- Cookie
	},
	["The Drowned City"] = {
		{ 3474 }, -- Zul'Alai
		{ 3475 }, -- Var'Taka
		{ 3476 }, -- Captain Dreadrise
		{ 3478 }, -- Deathless Marrow
		{ 3479 }, -- Min'loth the Serpent
	},
	["The Stockade"] = {
		{ 2756 }, -- Targorr the Dread
		{ 2757 }, -- Kam Deepfury
		{ 2758 }, -- Hamhock
		{ 2759 }, -- Dextren Ward
		{ 2760 }, -- Bazil Thredd
	},
	["Uldaman"] = {
		{ 547 }, -- Revelosh
		{ 548 }, -- The Lost Dwarves
		{ 549 }, -- Ironaya
		{ 551 }, -- Ancient Stone Keeper
		{ 552 }, -- Galgann Firehammer
		{ 553 }, -- Grimlok
		{ 554 }, -- Archaedas
	},
	["Upper Blackrock Spire"] = {
		{ 276, 3062 }, -- Pyroguard Emberseer
		{ 278, 3063 }, -- Warchief Rend Blackhand
		{ 279, 3068 }, -- The Beast
		{ 280, 3069 }, -- General Drakkisath
	},
	["Wailing Caverns"] = {
		{ 586 }, -- Lord Cobrahn
		{ 585 }, -- Lady Anacondra
		{ 587 }, -- Kresh
		{ 588 }, -- Lord Pythas
		{ 589 }, -- Skum
		{ 590 }, -- Lord Serpentis
		{ 591 }, -- Verdan the Everliving
		{ 592 }, -- Mutanus the Devourer
	},
	["Zul'Farrak"] = {
		{ 596 }, -- Theka the Martyr
		{ 595 }, -- Antu'sul
		{ 597 }, -- Witch Doctor Zum'rah
		{ 598 }, -- Nekrum Gutchewer
		{ 599 }, -- Shadowpriest Sezz'ziz
		{ 593 }, -- Hydromancer Velratha
		{ 594 }, -- Gahz'rilla
		{ 600 }, -- Chief Ukorz Sandscalp
	},
}
