-- Oseille — Tracking.lua
-- Résolveur de contexte : devine la source d'une variation d'or au moment où
-- elle survient, en croisant les fenêtres ouvertes (marchand/courrier/échange)
-- et des événements ponctuels (butin, quête, réparation).

local addonName, ns = ...

local Tracking = {}
ns.Tracking = Tracking

-- ─────────────────────────────────────────────────────────────────────────
-- Métadonnées des sources (clé → libellé FR + couleur), partagées avec l'UI.
-- order = ordre d'affichage ; kind = "income" | "expense" | "both".
-- ─────────────────────────────────────────────────────────────────────────
ns.SOURCES = {
	loot   = { label = "Butin",       color = { 1.00, 0.82, 0.00 }, kind = "income",  order = 1 },
	sell   = { label = "Vente",       color = { 0.40, 0.80, 1.00 }, kind = "income",  order = 2 },
	quest  = { label = "Quête",       color = { 0.60, 1.00, 0.60 }, kind = "income",  order = 3 },
	reward = { label = "Récompense",  color = { 0.30, 0.90, 0.80 }, kind = "income",  order = 4 },
	mail   = { label = "Courrier/HV", color = { 0.85, 0.60, 1.00 }, kind = "both",    order = 4 },
	trade  = { label = "Échange",     color = { 1.00, 0.70, 0.40 }, kind = "both",    order = 5 },
	buy    = { label = "Achat",       color = { 1.00, 0.45, 0.45 }, kind = "expense", order = 6 },
	repair = { label = "Réparation",  color = { 0.90, 0.50, 0.30 }, kind = "expense", order = 7 },
	other  = { label = "Autre",       color = { 0.70, 0.70, 0.70 }, kind = "both",    order = 8 },
}

-- Ordre de parcours stable des sources.
ns.SOURCE_ORDER = { "loot", "sell", "quest", "reward", "mail", "trade", "buy", "repair", "other" }

-- ─────────────────────────────────────────────────────────────────────────
-- État interne
-- ─────────────────────────────────────────────────────────────────────────
local context = nil        -- "merchant" | "mail" | "trade" | nil (fenêtre ouverte)
local pending = nil        -- "loot" | "quest" | "reward" (drapeau ponctuel one-shot)
local pendingRepair = false

-- Annule le drapeau ponctuel s'il n'a pas été consommé par un PLAYER_MONEY.
local function clearPendingSoon()
	C_Timer.After(0.5, function()
		pending = nil
		pendingRepair = false
	end)
end

-- ─────────────────────────────────────────────────────────────────────────
-- Résolution de la source pour un delta donné.
-- ─────────────────────────────────────────────────────────────────────────
function Tracking:ResolveSource(delta)
	local src

	if pending == "loot" then
		src = "loot"
	elseif pending == "quest" then
		src = "quest"
	elseif pending == "reward" then
		src = "reward"
	elseif context == "merchant" then
		if delta > 0 then
			src = "sell"
		else
			src = pendingRepair and "repair" or "buy"
		end
	elseif context == "mail" then
		src = "mail"
	elseif context == "trade" then
		src = "trade"
	else
		src = "other"
	end

	-- Les drapeaux ponctuels sont à usage unique.
	pending = nil
	pendingRepair = false
	return src
end

-- ─────────────────────────────────────────────────────────────────────────
-- Événements de contexte
-- ─────────────────────────────────────────────────────────────────────────
local frame = CreateFrame("Frame", "OseilleTrackingFrame")
local EVENTS = {
	"MERCHANT_SHOW", "MERCHANT_CLOSED",
	"MAIL_SHOW", "MAIL_CLOSED",
	"TRADE_SHOW", "TRADE_CLOSED",
	"CHAT_MSG_MONEY",
	"QUEST_TURNED_IN",
	"SHOW_LOOT_TOAST",
}
for _, e in ipairs(EVENTS) do frame:RegisterEvent(e) end

frame:SetScript("OnEvent", function(_, event, ...)
	if event == "MERCHANT_SHOW" then
		context = "merchant"
	elseif event == "MERCHANT_CLOSED" then
		context = nil
		pendingRepair = false
	elseif event == "MAIL_SHOW" then
		context = "mail"
	elseif event == "MAIL_CLOSED" then
		context = nil
	elseif event == "TRADE_SHOW" then
		context = "trade"
	elseif event == "TRADE_CLOSED" then
		context = nil
	elseif event == "CHAT_MSG_MONEY" then
		pending = "loot"
		clearPendingSoon()
	elseif event == "QUEST_TURNED_IN" then
		pending = "quest"
		clearPendingSoon()
	elseif event == "SHOW_LOOT_TOAST" then
		-- Récompenses de contenu (expéditions, délves, missions, bonus) :
		-- l'or arrive via une bannière de récompense, type "money".
		local typeIdentifier = ...
		if typeIdentifier == "money" then
			pending = "reward"
			clearPendingSoon()
		end
	end
end)

-- ─────────────────────────────────────────────────────────────────────────
-- Hooks pour distinguer la réparation des achats marchand.
-- Positionnent un drapeau « réparation » consommé par le PLAYER_MONEY suivant.
-- ─────────────────────────────────────────────────────────────────────────
local function flagRepair()
	if context == "merchant" then
		pendingRepair = true
		clearPendingSoon()
	end
end

if RepairAllItems then
	hooksecurefunc("RepairAllItems", flagRepair)
end
