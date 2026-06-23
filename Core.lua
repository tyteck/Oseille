-- Oseille — Core.lua
-- Initialisation, gestion des événements et capture des variations d'or.

local addonName, ns = ...

local DB = ns.DB

-- Solde de référence pour calculer les deltas.
local lastMoney = 0

local frame = CreateFrame("Frame", "OseilleEventFrame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_MONEY")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:RegisterEvent("PLAYER_ENTERING_WORLD")

frame:SetScript("OnEvent", function(_, event, ...)
	if event == "PLAYER_LOGIN" then
		DB:Initialize()
		DB:Today() -- s'assure que l'entrée du jour existe

		if ns.Minimap then ns.Minimap:Init() end
		if ns.UI then ns.UI:Refresh() end

	elseif event == "PLAYER_ENTERING_WORLD" then
		-- GetMoney() est fiable ici : on cale la référence et le solde réel.
		local money = DB:SyncCurrentGold()
		lastMoney = money or GetMoney()

		if ns.UI and ns.UI:IsShown() then ns.UI:Refresh() end

	elseif event == "PLAYER_MONEY" then
		local now = GetMoney()
		local delta = now - lastMoney
		local source = ns.Tracking and ns.Tracking:ResolveSource(delta) or "other"
		DB:RecordDelta(now, lastMoney, source)
		lastMoney = now

		if ns.UI and ns.UI:IsShown() then ns.UI:Refresh() end

	elseif event == "PLAYER_LOGOUT" then
		-- char.gold et day.close sont déjà tenus à jour en direct par
		-- PLAYER_MONEY / PLAYER_ENTERING_WORLD. On NE relit PAS GetMoney()
		-- ici car la lecture au logout est peu fiable (renvoie souvent 0)
		-- et écraserait la bonne valeur. On note juste la date.
		if DB.current then
			DB.current.lastSeen = GetServerTime()
		end
	end
end)

-- Commande slash : /oseille ou /os pour ouvrir/fermer la fenêtre.
SLASH_OSEILLE1 = "/oseille"
SLASH_OSEILLE2 = "/os"
SlashCmdList["OSEILLE"] = function(msg)
	if ns.UI then
		ns.UI:Toggle()
	end
end
