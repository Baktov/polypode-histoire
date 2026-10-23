-- Polypode Histoire: Locale — table de textes du module (traductions : Locales/*.lua), voir
-- Polypode/MODULES.md (« Langues »)

local _, ns = ...
local P = Polypode

-- L[texte français] → texte dans la langue choisie dans Polypode ; avec un Polypode trop ancien
-- (sans traductions), le texte français.
ns.L = P.NewLocale and P.NewLocale() or setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})

-- Appelle fn quand la langue d'affichage est connue : textes rangés au chargement (bouton de la
-- barre de titre, aide de /poly histoire...). Tout de suite avec un Polypode plus ancien.
function ns.OnLanguageApplied(fn)
	if P.OnLanguageApplied then
		P.OnLanguageApplied(fn)
	else
		fn()
	end
end
