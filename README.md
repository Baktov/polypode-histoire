# Polypode Histoire

**Journal chronologique commun** de tous vos personnages pour
[Polypode](https://github.com/Baktov/polypode), sous forme d'addon séparé : connexions,
déconnexions, groupes d'équipe, gouffres, donjons, clés mythiques+, boss de raid, hauts faits,
niveaux et niveau d'objet, rangés par année, mois et jour.

Nécessite **Polypode**.

---

## Installation

1. Installer d'abord **Polypode** (dépendance obligatoire).
2. Placer le dossier `Polypode_Histoire` dans `World of Warcraft/_retail_/Interface/AddOns/`
   (et dans `_classic_beta_/Interface/AddOns/` pour WoW Forever).
3. Placer **aussi** son sous-dossier `Polypode_Histoire_Archive` directement dans
   `Interface/AddOns/` (WoW ne lit pas un addon rangé dans un autre ; une jonction `mklink /J`
   convient).
4. Cocher « Polypode Histoire » et « Polypode Histoire Archive » dans la liste des AddOns, **sur
   chaque personnage** : chacun note ses propres événements et les partage avec les autres.

---

## Utilisation

Le bouton **Histoire** (barre de titre de Polypode) ou `/poly histoire` ouvre la fenêtre du
journal : un arbre **Année > Mois > Jour**, du plus récent au plus ancien. **Clic** sur une année,
un mois ou un jour : le replier ou le déplier (par défaut, seuls l'année, le mois et le jour en
cours sont dépliés ; vos choix sont gardés). Le bouton **Tout replier** / **Tout déplier** agit sur
tout l'arbre. Le nombre d'événements est indiqué à droite de chaque année, mois et jour.

Les jours de **sortie d'un patch** (date des serveurs européens) sont signalés **en vert** à droite
du jour, avec le nom du patch (« Mercredi 14 octobre  Patch 12.1.5 « La Promesse de demain » »),
même sans événement ce jour-là, dans les mois affichés ; un patch annoncé à venir est toujours
affiché, marqué « (à venir) » (Retail seulement). Case **Ext** à droite du titre : afficher ou
non ces jours de patchs et d'extensions (cochée par défaut).

**Filtres** (cases à gauche de la barre de titre, libellés abrégés, nom complet au survol) :
**Con.** connexions, **H-F** hauts faits, **Gou.** gouffres, **Don.** donjons (avec les clés M+),
**Rai.** raids (entrées comprises), **Col.** collections (jouets, montures, mascottes), **Rép.**
renom et réputation et **Soc.** social (amis, guildes, communautés). Aucune case cochée (par défaut) :
tout le journal ; sinon, seuls les événements des catégories cochées, les jours sans événement
retenu étant masqués. Le choix est gardé.

Dans un jour, les événements sont dans l'ordre de l'heure :

| Événement | Exemple |
|---|---|
| Connexion / déconnexion (avec le temps joué depuis la connexion) | 21:05 Mordsith se connecte · 23:10 Mordsith se déconnecte (2 h 05) |
| Équipe groupée au complet (noté par son leader) | 21:07 L'équipe « Midnight » se groupe (5 personnages) |
| Entrée dans un gouffre, un donjon ou un raid | 21:15 Mordsith, Darà entrent dans le gouffre « Le Puits » |
| Gouffre terminé (avec la section pour un gouffre en plusieurs parties) | 21:40 Mordsith, Darà terminent le gouffre « Le Puits » : « … » (palier 8, 25 min) |
| Donjon terminé (dernier boss) | 22:10 … terminent le donjon « … » (Héroïque, 32 min) |
| Clé mythique+ terminée (durée : temps du chrono) | 22:45 … terminent la clé « … » +10 (dans les temps, 28 min) |
| Boss de raid vaincu | 23:20 … vainquent « … » (raid, difficulté, 12 min) |
| Haut fait (**clic** : ouvrir la fenêtre des hauts faits du jeu sur lui) | Mordsith obtient le haut fait « … » |
| Niveau | Darà atteint le niveau 90 |
| Niveau d'objet (sans décimales, seulement quand il dépasse le plus haut connu) | Corwin passe au niveau d'objet 245 (+3) |
| Jouet, monture, mascotte obtenus | Mordsith obtient la monture « … » |
| Palier de renom | Mordsith atteint le renom 12 auprès de « … » |
| Ami ajouté ou retiré (du personnage, ou Battle.net : sans nom de personnage, le compte étant commun) | Mordsith ajoute « Bob-Elune » à ses amis · Ami Battle.net ajouté : « Zed » |
| Guilde ou communauté rejointe ou quittée | Mordsith rejoint la guilde « … » · Mordsith quitte la communauté « … » |
| Rang de réputation atteint (amitié comprise ; seulement en montant, la première lecture d'une faction sert de référence) | Mordsith devient « Révéré » auprès de « … » |

La **durée** entre parenthèses part de l'entrée dans l'instance, ou de la fin précédente dans la même
instance (section de gouffre, boss de raid précédent) ; revenir dans l'instance moins de 15 minutes
après l'avoir quittée (mort, sortie) ne compte pas comme une nouvelle entrée. Dans un jour, les
événements vont du **plus récent au plus ancien**, comme les jours.

Le même événement vécu par plusieurs personnages à moins de 5 minutes d'écart tient sur **une
ligne** ; **au survol**, l'heure exacte de chacun.

**Clic droit** sur une ligne : la **supprimer** du journal, après confirmation (tous les
personnages de la ligne), ici et sur les clients connectés.

**Journal commun** : chaque personnage envoie ses événements aux autres clients connectés, et
renvoie ceux de sa session à chaque client qui se connecte ; tous les clients tiennent donc le
même journal. Une déconnexion est notée dès qu'on la demande (menu, `/logout`, `/quit`) et
retirée si elle est annulée ; `/reload` n'en est pas une. Une **déco-reco de moins de 3 minutes**
n'est pas notée (le personnage reste connecté dans le journal), ni une **session de moins de
3 minutes** (connexion puis déconnexion).

### Taille du journal et export

L'en-tête de la fenêtre donne le nombre d'événements et la taille estimée du journal dans son
fichier de sauvegarde. Au-delà de **2 Mo**, elle passe en orange (« export conseillé ») et un
message le rappelle à la connexion ; au-delà de **5 Mo**, en rouge.

Le bouton **Exporter** déplace les jours **antérieurs au mois précédent** (on garde toujours le
mois en cours et le précédent) vers l'**archive** : le fichier
`WTF\Account\<compte>\SavedVariables\Polypode_Histoire_Archive.lua`, porté par l'addon
« Polypode Histoire Archive », chargé seulement à ce moment-là (jamais au lancement : il ne ralentit
rien). L'archive est **complétée** à chaque export, jamais remplacée ; les jours exportés sont
ensuite retirés du journal, ici et sur les clients connectés. Elle est écrite à la déconnexion ou
au `/reload` du client qui a exporté.

### Format des données

Journal (`PolypodeHistoireData`) et archive (`PolypodeHistoireArchive`) ont le même format,
prévu pour être lu par un logiciel tiers :

```lua
days = {
	["2026-10-11"] = {
		"1791745500~Mordsith-Elune~in",
		"1791747600~Mordsith-Elune~delve~Le Puits~8",
	},
}
```

Chaque événement : `heure~personnage~type~champs`, heure = secondes depuis 1970 (heure serveur),
personnage = `nom-royaume`, jour = date locale. Types et champs :

| Type | Champs |
|---|---|
| `in` / `out` | — |
| `grp` | équipe, nombre de membres |
| `lvl` | niveau |
| `ach` | identifiant du haut fait |
| `ilvl` | nouveau niveau d'objet, ancien |
| `delve` | nom du gouffre, palier (« 0 » dans les anciens événements : inconnu, non affiché), section, durée (secondes) |
| `enter` | nom de l'instance, identifiant de difficulté, genre (`delve` / `party` / `raid`) |
| `dng` | nom du donjon, identifiant de difficulté, durée |
| `mplus` | nom du donjon, niveau de la clé, dans les temps (1 / 0), améliorations de la clé, durée (chrono) |
| `boss` | nom du boss, identifiant de difficulté, nom du raid, durée |
| `toy` / `mount` / `pet` | identifiant (objet, monture, espèce de mascotte), nom |
| `renown` | identifiant de la faction majeure, palier, nom de la faction |
| `friend` | nom (BattleTag sans numéro pour un ami Battle.net), `+` / `-`, `c` (personnage) / `b` (Battle.net) |
| `guild` | nom de la guilde, `+` / `-` |
| `club` | nom de la communauté, `+` / `-`, `c` / `b` |
| `rep` | identifiant de la faction, rang (texte), nom de la faction, numéro du rang |

---

## Version

`1.9.0` : social : amis (du personnage et Battle.net) ajoutés ou retirés, guildes et communautés rejointes ou quittées ; filtre « Soc. ».
`1.8.0` : jouets, montures et mascottes obtenus ; paliers de renom et rangs de réputation atteints ; filtres « Col. » et « Rép. ». Nouveau fichier de sauvegarde par personnage (`PolypodeHistoireChar`) : redémarrer le jeu (un /reload ne suffit pas).
`1.7.0` : patchs annoncés à venir affichés (« à venir ») ; case « Ext » à droite du titre pour afficher ou masquer les jours de patchs et d'extensions.
`1.6.0` : jours de sortie des patchs (Midnight) en vert avec leur nom, dans les mois affichés.
`1.5.1` : filtres : libellés abrégés (Con., H-F, Gou., Don., Rai.), nom complet dans l'infobulle ; fenêtre moins large possible.
`1.5.0` : filtres dans la barre de titre (connexions, hauts faits, gouffres, donjons, raids) ; aucun coché = tout le journal.
`1.4.0` : événements d'un jour du plus récent au plus ancien ; entrée dans un gouffre, un donjon ou un raid notée, et durée affichée à la fin (gouffre, section, donjon, clé M+, boss de raid).
`1.3.0` : temps joué affiché à la déconnexion ; hauts faits affichés par leur nom (et non plus leur numéro), clic pour les ouvrir dans la fenêtre des hauts faits ; gouffres : palier lu dans l'en-tête du scénario (il valait 0 en solo) et section terminée notée.
`1.2.0` : clic droit sur une entrée pour la supprimer du journal (avec confirmation, synchronisé entre clients).
`1.1.0` : déco-reco et sessions de moins de 3 minutes non notées dans le journal.
`1.0.0` : première version : journal commun synchronisé entre clients (connexions, déconnexions, équipe groupée, gouffres, donjons, clés M+, boss de raid, hauts faits, niveaux, niveau d'objet), fenêtre Année > Mois > Jour repliable, événements de plusieurs personnages réunis, avertissement de taille et export vers l'archive Polypode Histoire Archive.
