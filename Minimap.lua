-- Oseille — Minimap.lua
-- Bouton minimap natif (sans dépendance) pour ouvrir/fermer la fenêtre.

local addonName, ns = ...

local Minimap = {}
ns.Minimap = Minimap

local DEFAULT_ANGLE = 220 -- degrés

-- Place le bouton sur le pourtour de la minicarte selon l'angle sauvegardé.
local function UpdatePosition(btn)
	local angle = math.rad(OseilleDB.settings.minimapAngle or DEFAULT_ANGLE)
	local radius = (_G.Minimap:GetWidth() / 2) + 8
	local x = math.cos(angle) * radius
	local y = math.sin(angle) * radius
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", _G.Minimap, "CENTER", x, y)
end

-- Recalcule l'angle pendant le glissement, d'après la position du curseur.
local function OnDragUpdate(btn)
	local mx, my = _G.Minimap:GetCenter()
	local scale = _G.Minimap:GetEffectiveScale()
	local px, py = GetCursorPosition()
	px, py = px / scale, py / scale
	local angle = math.atan2(py - my, px - mx)
	OseilleDB.settings.minimapAngle = math.deg(angle)
	UpdatePosition(btn)
end

function Minimap:Init()
	if self.button then
		UpdatePosition(self.button)
		return
	end

	local btn = CreateFrame("Button", "OseilleMinimapButton", _G.Minimap)
	btn:SetSize(31, 31)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(8)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:RegisterForDrag("LeftButton")

	-- Icône (pièce d'or).
	local icon = btn:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetTexture("Interface\\ICONS\\INV_Misc_Coin_01")
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:SetPoint("CENTER", btn, "CENTER", 0, 1)

	-- Bordure circulaire native des boutons de minicarte.
	local overlay = btn:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")

	-- Surbrillance au survol.
	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	btn:SetScript("OnClick", function()
		ns.UI:Toggle()
	end)

	btn:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	btn:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)

	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Oseille")
		GameTooltip:AddLine("Clic : ouvrir/fermer le suivi de l'argent", 1, 1, 1)
		GameTooltip:AddLine("Glisser : déplacer le bouton", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	self.button = btn
	UpdatePosition(btn)
end
