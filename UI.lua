-- Oseille — UI.lua
-- Fenêtre principale : liste des personnages, sélecteur de période, stats et courbe.

local addonName, ns = ...

local DB = ns.DB
local UI = {}
ns.UI = UI

local PERIODS = {
	{ key = "day",   label = "Jour" },
	{ key = "week",  label = "Semaine" },
	{ key = "month", label = "Mois" },
	{ key = "year",  label = "Année" },
	{ key = "all",   label = "Tout" },
}

local LEFT_W = 200
local FRAME_W = 760
local FRAME_H = 500
local LEGEND_COL_W = 248

-- ─────────────────────────────────────────────────────────────────────────
-- Construction de la fenêtre (paresseuse, au premier affichage).
-- ─────────────────────────────────────────────────────────────────────────

function UI:Build()
	if self.frame then return end

	local f = CreateFrame("Frame", "OseilleFrame", UIParent, "PortraitFrameTemplate")
	f:SetSize(FRAME_W, FRAME_H)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	tinsert(UISpecialFrames, "OseilleFrame") -- fermeture avec Échap

	if f.SetTitle then f:SetTitle("Oseille") end
	if f.SetPortraitToAsset then
		f:SetPortraitToAsset("Interface\\ICONS\\INV_Misc_Coin_01")
	end

	-- Les frames sont affichées par défaut : on la masque pour que le
	-- premier Toggle l'ouvre (sinon il faudrait cliquer deux fois).
	f:Hide()

	self.frame = f

	-- En-tête : or total possédé (décalé à droite du portrait).
	local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	header:SetPoint("TOPLEFT", f, "TOPLEFT", 70, -32)
	header:SetPoint("RIGHT", f, "RIGHT", -16, 0)
	header:SetJustifyH("LEFT")
	self.headerText = header

	-- ── Panneau gauche : liste des personnages ──
	local left = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	left:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -56)
	left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 14)
	left:SetWidth(LEFT_W)
	self.leftPanel = left
	self.charButtons = {}

	-- ── Zone droite ──
	local rightX = LEFT_W + 18

	-- Boutons de période.
	self.periodButtons = {}
	local prev
	for i, p in ipairs(PERIODS) do
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(72, 22)
		if i == 1 then
			b:SetPoint("TOPLEFT", f, "TOPLEFT", rightX, -54)
		else
			b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
		end
		b:SetText(p.label)
		b.periodKey = p.key
		b:SetScript("OnClick", function()
			UI.selectedPeriod = p.key
			OseilleDB.settings.period = p.key
			UI:Refresh()
		end)
		self.periodButtons[i] = b
		prev = b
	end

	-- Panneau de stats (Gagné / Dépensé / Net).
	local statsY = -86
	local function makeStat(anchorX, labelText, labelColor)
		local box = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
		box:SetSize(168, 50)
		box:SetPoint("TOPLEFT", f, "TOPLEFT", anchorX, statsY)

		local lbl = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		lbl:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -8)
		lbl:SetText(labelText)
		lbl:SetTextColor(unpack(labelColor))

		local val = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		val:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 10, 8)
		return val
	end

	self.statEarned = makeStat(rightX, "Gagné", { 0.4, 1.0, 0.4 })
	self.statSpent = makeStat(rightX + 178, "Dépensé", { 1.0, 0.45, 0.45 })
	self.statNet = makeStat(rightX + 356, "Net", { 1.0, 0.95, 0.6 })

	-- ── Répartition par source (deux colonnes) ──
	local breakdown = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	breakdown:SetPoint("TOPLEFT", f, "TOPLEFT", rightX, statsY - 60)
	breakdown:SetPoint("RIGHT", f, "RIGHT", -14, 0)
	breakdown:SetHeight(120)
	self.breakdown = breakdown
	self.legendLines = { income = {}, expense = {} }

	local incHeader = breakdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	incHeader:SetPoint("TOPLEFT", breakdown, "TOPLEFT", 12, -6)
	incHeader:SetText("Gagné par source")
	incHeader:SetTextColor(0.4, 1.0, 0.4)

	local expHeader = breakdown:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	expHeader:SetPoint("TOPLEFT", breakdown, "TOPLEFT", LEGEND_COL_W + 26, -6)
	expHeader:SetText("Dépensé par source")
	expHeader:SetTextColor(1.0, 0.45, 0.45)

	-- Zone du graphique.
	local graphFrame = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	graphFrame:SetPoint("TOPLEFT", f, "TOPLEFT", rightX, statsY - 186)
	graphFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
	self.graphFrame = graphFrame
	self.graph = ns.Graph.New(graphFrame)

	self.selectedKey = "all"
	self.selectedPeriod = (OseilleDB and OseilleDB.settings and OseilleDB.settings.period) or "week"
end

-- ─────────────────────────────────────────────────────────────────────────
-- Liste des personnages
-- ─────────────────────────────────────────────────────────────────────────

function UI:_GetCharButton(index)
	local b = self.charButtons[index]
	if not b then
		b = CreateFrame("Button", nil, self.leftPanel)
		b:SetHeight(22)
		b:SetPoint("TOPLEFT", self.leftPanel, "TOPLEFT", 6, -6 - (index - 1) * 24)
		b:SetPoint("TOPRIGHT", self.leftPanel, "TOPRIGHT", -6, -6 - (index - 1) * 24)

		b.hl = b:CreateTexture(nil, "BACKGROUND")
		b.hl:SetAllPoints()
		b.hl:SetColorTexture(1, 1, 1, 0.12)
		b.hl:Hide()

		b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.name:SetPoint("LEFT", b, "LEFT", 2, 0)
		b.name:SetJustifyH("LEFT")

		b.gold = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.gold:SetPoint("RIGHT", b, "RIGHT", -2, 0)
		b.gold:SetJustifyH("RIGHT")

		b:SetScript("OnEnter", function(self) if self.charKey ~= UI.selectedKey then self.hl:Show() end end)
		b:SetScript("OnLeave", function(self) if self.charKey ~= UI.selectedKey then self.hl:Hide() end end)

		self.charButtons[index] = b
	end
	b:Show()
	return b
end

function UI:RefreshCharList()
	-- Cache tous les boutons existants.
	for _, b in ipairs(self.charButtons) do b:Hide() end

	local index = 1

	-- Entrée "Total" en tête.
	local total = self:_GetCharButton(index)
	total.charKey = "all"
	total.name:SetText("|cffffd700Total|r")
	total.gold:SetText(ns.FormatGoldShort(DB:GetCurrentGold("all")) .. " po")
	total:SetScript("OnClick", function() UI.selectedKey = "all"; UI:Refresh() end)
	index = index + 1

	-- Un bouton par personnage, trié par or décroissant.
	for _, info in ipairs(DB:GetCharacterList()) do
		local b = self:_GetCharButton(index)
		b.charKey = info.key

		local color = (info.class and RAID_CLASS_COLORS[info.class]) or NORMAL_FONT_COLOR
		b.name:SetText(string.format("|c%s%s|r", color.colorStr or "ffffffff", info.name))
		b.gold:SetText(ns.FormatGoldShort(info.gold) .. " po")
		b:SetScript("OnClick", function() UI.selectedKey = info.key; UI:Refresh() end)
		index = index + 1
	end

	-- Met en surbrillance la sélection courante.
	for _, b in ipairs(self.charButtons) do
		if b:IsShown() and b.charKey == self.selectedKey then
			b.hl:Show()
		else
			b.hl:Hide()
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────
-- Répartition par source
-- ─────────────────────────────────────────────────────────────────────────

function UI:_MakeLegendLine()
	local line = CreateFrame("Frame", nil, self.breakdown)
	line:SetSize(LEGEND_COL_W, 15)

	line.swatch = line:CreateTexture(nil, "OVERLAY")
	line.swatch:SetSize(10, 10)
	line.swatch:SetPoint("LEFT", line, "LEFT", 0, 0)

	line.label = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	line.label:SetPoint("LEFT", line.swatch, "RIGHT", 5, 0)
	line.label:SetJustifyH("LEFT")

	line.amount = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	line.amount:SetPoint("RIGHT", line, "RIGHT", 0, 0)
	line.amount:SetJustifyH("RIGHT")

	return line
end

-- Remplit une colonne (income ou expense) avec les sources non nulles.
function UI:_FillLegend(pool, totals, colX)
	for _, l in ipairs(pool) do l:Hide() end

	local sum = 0
	for _, v in pairs(totals) do sum = sum + v end

	local row = 0
	for _, src in ipairs(ns.SOURCE_ORDER) do
		local v = totals[src]
		if v and v > 0 then
			row = row + 1
			local line = pool[row]
			if not line then
				line = self:_MakeLegendLine()
				pool[row] = line
			end
			local meta = ns.SOURCES[src]
			line.swatch:SetColorTexture(meta.color[1], meta.color[2], meta.color[3])
			line.label:SetText(meta.label)
			local pct = sum > 0 and math.floor(v / sum * 100 + 0.5) or 0
			line.amount:SetText(string.format("%s po  |cff909090%d%%|r", ns.FormatGoldShort(v), pct))
			line:ClearAllPoints()
			line:SetPoint("TOPLEFT", self.breakdown, "TOPLEFT", colX, -24 - (row - 1) * 15)
			line:Show()
		end
	end
end

function UI:RefreshBreakdown(income, expense)
	self:_FillLegend(self.legendLines.income, income, 12)
	self:_FillLegend(self.legendLines.expense, expense, LEGEND_COL_W + 26)
end

-- ─────────────────────────────────────────────────────────────────────────
-- Rafraîchissement global
-- ─────────────────────────────────────────────────────────────────────────

function UI:Refresh()
	if not self.frame then return end

	-- État des boutons de période.
	for _, b in ipairs(self.periodButtons) do
		if b.periodKey == self.selectedPeriod then
			b:LockHighlight()
		else
			b:UnlockHighlight()
		end
	end

	-- En-tête.
	self.headerText:SetText("Or total : " .. ns.FormatMoney(DB:GetCurrentGold("all")))

	self:RefreshCharList()

	-- Calcul des données de la période.
	local fromDay, toDay = DB:GetPeriodRange(self.selectedPeriod)
	local series
	if self.selectedKey == "all" then
		series = DB:GetTotalSeries(fromDay, toDay)
	else
		series = DB:GetCharSeries(self.selectedKey, fromDay, toDay)
	end

	local earned, spent, net = DB:GetTotals(self.selectedKey, fromDay, toDay)
	self.statEarned:SetText(ns.FormatMoney(earned))
	self.statSpent:SetText(ns.FormatMoney(spent))
	if net >= 0 then
		self.statNet:SetText("|cff66ff66+|r " .. ns.FormatMoney(net))
	else
		self.statNet:SetText("|cffff6666-|r " .. ns.FormatMoney(-net))
	end

	-- Répartition par source.
	local income, expense = DB:GetSourceTotals(self.selectedKey, fromDay, toDay)
	self:RefreshBreakdown(income, expense)

	self.graph:Draw(series)
end

-- ─────────────────────────────────────────────────────────────────────────
-- API publique
-- ─────────────────────────────────────────────────────────────────────────

function UI:IsShown()
	return self.frame and self.frame:IsShown()
end

function UI:Toggle()
	self:Build()
	if self.frame:IsShown() then
		self.frame:Hide()
	else
		self.frame:Show()
		self:Refresh()
	end
end
