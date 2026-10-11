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

Dans un jour, les événements sont dans l'ordre de l'heure :

| Événement | Exemple |
|---|---|
| Connexion / déconnexion | 21:05 Mordsith se connecte |
| Équipe groupée au complet (noté par son leader) | 21:07 L'équipe « Midnight » se groupe (5 personnages) |
| Gouffre terminé | 21:40 Mordsith, Darà terminent le gouffre « Le Puits » (palier 8) |
| Donjon terminé (dernier boss) | 22:10 … terminent le donjon « … » (Héroïque) |
| Clé mythique+ terminée | 22:45 … terminent la clé « … » +10 (dans les temps) |
| Boss de raid vaincu | 23:20 … vainquent « … » (raid, difficulté) |
| Haut fait | Mordsith obtient le haut fait « … » |
| Niveau | Darà atteint le niveau 90 |
| Niveau d'objet (sans décimales, seulement quand il dépasse le plus haut connu) | Corwin passe au niveau d'objet 245 (+3) |

Le même événement vécu par plusieurs personnages à moins de 5 minutes d'écart tient sur **une
ligne** ; **au survol**, l'heure exacte de chacun.

**Journal commun** : chaque personnage envoie ses événements aux autres clients connectés, et
renvoie ceux de sa session à chaque client qui se connecte ; tous les clients tiennent donc le
même journal. Une déconnexion est notée dès qu'on la demande (menu, `/logout`, `/quit`) et
retirée si elle est annulée ; `/reload` n'en est pas une.

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
| `delve` | nom du gouffre, palier |
| `dng` | nom du donjon, identifiant de difficulté |
| `mplus` | nom du donjon, niveau de la clé, dans les temps (1 / 0), améliorations de la clé |
| `boss` | nom du boss, identifiant de difficulté, nom du raid |

---

## Version

`1.0.0` : première version : journal commun synchronisé entre clients (connexions, déconnexions, équipe groupée, gouffres, donjons, clés M+, boss de raid, hauts faits, niveaux, niveau d'objet), fenêtre Année > Mois > Jour repliable, événements de plusieurs personnages réunis, avertissement de taille et export vers l'archive Polypode Histoire Archive.
