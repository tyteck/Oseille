-- Oseille — Graph.lua
-- Rendu natif d'une courbe via frame:CreateLine, avec axes, grille et libellés.

local addonName, ns = ...

-- ─────────────────────────────────────────────────────────────────────────
-- Utilitaires de formatage de l'argent (partagés avec l'UI).
-- ─────────────────────────────────────────────────────────────────────────

-- Montant complet avec icônes or/argent/cuivre natives.
function ns.FormatMoney(copper)
	return GetCoinTextureString(math.max(0, math.floor(copper or 0)))
end

-- Format court en pièces d'or pour les axes : 12.3k, 1.5M, etc.
function ns.FormatGoldShort(copper)
	local gold = (copper or 0) / 10000
	if gold >= 1e6 then
		return string.format("%.1fM", gold / 1e6)
	elseif gold >= 1e3 then
		return string.format("%.1fk", gold / 1e3)
	else
		return string.format("%d", gold)
	end
end

-- ─────────────────────────────────────────────────────────────────────────
-- Module Graph
-- ─────────────────────────────────────────────────────────────────────────

local Graph = {}
ns.Graph = Graph

local PAD_LEFT = 52
local PAD_BOTTOM = 22
local PAD_TOP = 12
local PAD_RIGHT = 14

local COLOR_AXIS = { 0.6, 0.6, 0.6, 0.8 }
local COLOR_GRID = { 0.35, 0.35, 0.35, 0.4 }
local COLOR_LINE = { 1.0, 0.82, 0.0, 1.0 } -- or
local COLOR_FILL = { 1.0, 0.82, 0.0, 0.10 }

-- Crée un objet graphe attaché à un frame parent.
function Graph.New(parent)
	local self = setmetatable({}, { __index = Graph })

	local c = CreateFrame("Frame", nil, parent)
	c:SetAllPoints(parent)
	self.container = c

	self.linePool = {}      -- lignes de données réutilisables
	self.gridPool = {}      -- lignes de grille/axes réutilisables
	self.labelPool = {}     -- FontStrings d'axes réutilisables
	self.lineCount = 0
	self.gridCount = 0
	self.labelCount = 0

	-- Message affiché quand il n'y a pas de données.
	self.empty = c:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	self.empty:SetPoint("CENTER")
	self.empty:SetText("Aucune donnée pour cette période")
	self.empty:Hide()

	return self
end

-- ── Pools ────────────────────────────────────────────────────────────────

function Graph:_GetLine(pool, counterKey)
	self[counterKey] = self[counterKey] + 1
	local idx = self[counterKey]
	local line = pool[idx]
	if not line then
		line = self.container:CreateLine(nil, "ARTWORK")
		pool[idx] = line
	end
	line:Show()
	return line
end

function Graph:_GetLabel()
	self.labelCount = self.labelCount + 1
	local lbl = self.labelPool[self.labelCount]
	if not lbl then
		lbl = self.container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		self.labelPool[self.labelCount] = lbl
	end
	lbl:Show()
	return lbl
end

function Graph:Clear()
	for _, l in ipairs(self.linePool) do l:Hide() end
	for _, l in ipairs(self.gridPool) do l:Hide() end
	for _, l in ipairs(self.labelPool) do l:Hide(); l:SetText("") end
	self.lineCount = 0
	self.gridCount = 0
	self.labelCount = 0
end

-- ── Dessin ───────────────────────────────────────────────────────────────

-- series : { {x = dayId, y = copper}, ... } triée par x croissant.
-- opts   : { color = {r,g,b,a} } (optionnel)
function Graph:Draw(series, opts)
	self:Clear()

	local w = self.container:GetWidth()
	local h = self.container:GetHeight()
	if not w or w <= 0 or not h or h <= 0 then
		-- Le frame n'est pas encore dimensionné : on réessaie au prochain frame.
		C_Timer.After(0, function() self:Draw(series, opts) end)
		return
	end

	if not series or #series == 0 then
		self.empty:Show()
		return
	end
	self.empty:Hide()

	opts = opts or {}
	local lineColor = opts.color or COLOR_LINE

	local plotW = w - PAD_LEFT - PAD_RIGHT
	local plotH = h - PAD_TOP - PAD_BOTTOM
	if plotW <= 0 or plotH <= 0 then return end

	-- Bornes de valeur.
	local minY, maxY = math.huge, -math.huge
	for _, p in ipairs(series) do
		if p.y < minY then minY = p.y end
		if p.y > maxY then maxY = p.y end
	end
	if minY == maxY then
		-- Évite une division par zéro : marge artificielle.
		maxY = maxY + 10000
		minY = math.max(0, minY - 10000)
	end
	-- On démarre l'axe Y à 0 si les valeurs sont positives, sinon à minY.
	if minY > 0 then minY = 0 end

	local n = #series
	local function px(i)
		if n == 1 then return PAD_LEFT + plotW / 2 end
		return PAD_LEFT + (i - 1) / (n - 1) * plotW
	end
	local function py(value)
		return PAD_BOTTOM + (value - minY) / (maxY - minY) * plotH
	end

	-- ── Grille horizontale + libellés Y ──
	local Y_LINES = 4
	for i = 0, Y_LINES do
		local value = minY + (maxY - minY) * (i / Y_LINES)
		local y = PAD_BOTTOM + (i / Y_LINES) * plotH

		local grid = self:_GetLine(self.gridPool, "gridCount")
		grid:SetThickness(1)
		grid:SetColorTexture(unpack(i == 0 and COLOR_AXIS or COLOR_GRID))
		grid:SetStartPoint("BOTTOMLEFT", self.container, PAD_LEFT, y)
		grid:SetEndPoint("BOTTOMLEFT", self.container, PAD_LEFT + plotW, y)

		local lbl = self:_GetLabel()
		lbl:ClearAllPoints()
		lbl:SetPoint("RIGHT", self.container, "BOTTOMLEFT", PAD_LEFT - 4, y)
		lbl:SetText(ns.FormatGoldShort(value))
	end

	-- ── Axe Y (vertical) ──
	local axisY = self:_GetLine(self.gridPool, "gridCount")
	axisY:SetThickness(1)
	axisY:SetColorTexture(unpack(COLOR_AXIS))
	axisY:SetStartPoint("BOTTOMLEFT", self.container, PAD_LEFT, PAD_BOTTOM)
	axisY:SetEndPoint("BOTTOMLEFT", self.container, PAD_LEFT, PAD_BOTTOM + plotH)

	-- ── Libellés X (premier, milieu, dernier) ──
	local function dayLabel(dayId)
		local t = dayId * 86400
		return date("%d/%m", t)
	end
	local xPositions = { 1, math.ceil(n / 2), n }
	local seen = {}
	for _, i in ipairs(xPositions) do
		if not seen[i] and series[i] then
			seen[i] = true
			local lbl = self:_GetLabel()
			lbl:ClearAllPoints()
			lbl:SetPoint("TOP", self.container, "BOTTOMLEFT", px(i), PAD_BOTTOM - 3)
			lbl:SetText(dayLabel(series[i].x))
		end
	end

	-- ── Remplissage sous la courbe (verticales légères) ──
	for i = 1, n do
		local x = px(i)
		local yTop = py(series[i].y)
		local fill = self:_GetLine(self.linePool, "lineCount")
		fill:SetThickness(math.max(1, plotW / n))
		fill:SetColorTexture(unpack(COLOR_FILL))
		fill:SetStartPoint("BOTTOMLEFT", self.container, x, PAD_BOTTOM)
		fill:SetEndPoint("BOTTOMLEFT", self.container, x, yTop)
	end

	-- ── Courbe (segments entre points consécutifs) ──
	for i = 1, n - 1 do
		local seg = self:_GetLine(self.linePool, "lineCount")
		seg:SetThickness(2)
		seg:SetColorTexture(unpack(lineColor))
		seg:SetStartPoint("BOTTOMLEFT", self.container, px(i), py(series[i].y))
		seg:SetEndPoint("BOTTOMLEFT", self.container, px(i + 1), py(series[i + 1].y))
	end
end
