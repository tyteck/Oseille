-- Oseille — Database.lua
-- Modèle de données, initialisation et agrégation par période.

local addonName, ns = ...

local DB = {}
ns.DB = DB

local SECONDS_PER_DAY = 86400

-- Renvoie l'identifiant de jour (jours depuis l'epoch, heure serveur).
function DB:DayId(t)
	t = t or GetServerTime()
	return math.floor(t / SECONDS_PER_DAY)
end

-- Clé unique du personnage : "Nom-Royaume".
function DB:CharKey(name, realm)
	return (name or UnitName("player")) .. "-" .. (realm or GetRealmName())
end

-- Initialise la SavedVariable globale et la structure du personnage courant.
-- Appelée à PLAYER_LOGIN, une fois OseilleDB chargée.
function DB:Initialize()
	OseilleDB = OseilleDB or {}
	OseilleDB.characters = OseilleDB.characters or {}
	OseilleDB.settings = OseilleDB.settings or { period = "week", scope = "all" }

	local key = self:CharKey()
	local char = OseilleDB.characters[key]
	if not char then
		char = { days = {} }
		OseilleDB.characters[key] = char
	end
	char.days = char.days or {}

	local _, class = UnitClass("player")
	char.name = UnitName("player")
	char.realm = GetRealmName()
	char.class = class
	char.faction = UnitFactionGroup("player")
	-- GetMoney() peut renvoyer 0 tant que les données ne sont pas chargées :
	-- on ne remplace une valeur déjà connue que par une lecture > 0.
	local money = GetMoney()
	if money > 0 or char.gold == nil then
		char.gold = money
	end
	char.lastSeen = GetServerTime()

	self.currentKey = key
	self.current = char
	return char
end

-- Cale le solde du personnage courant sur une lecture fiable de GetMoney().
-- À appeler depuis PLAYER_ENTERING_WORLD (lecture garantie disponible).
-- Renvoie le solde lu (en cuivre), ou nil si la lecture n'est pas fiable.
function DB:SyncCurrentGold()
	local char = self.current
	if not char then return end
	local money = GetMoney()
	if money <= 0 then return end -- lecture non fiable : on garde la valeur stockée
	char.gold = money
	local day = self:Today(char)
	day.close = money
	char.lastSeen = GetServerTime()
	return money
end

-- Renvoie (et crée si besoin) l'agrégat du jour pour le personnage courant.
function DB:Today(char)
	char = char or self.current
	local dayId = self:DayId()
	local day = char.days[dayId]
	if not day then
		day = { close = char.gold or 0, earned = 0, spent = 0, income = {}, expense = {} }
		char.days[dayId] = day
	end
	day.income = day.income or {}
	day.expense = day.expense or {}
	return day, dayId
end

-- Enregistre une variation d'or pour le personnage courant.
-- source : clé de ns.SOURCES (ex. "loot", "sell", "buy"...) ; défaut "other".
function DB:RecordDelta(newMoney, oldMoney, source)
	local char = self.current
	if not char then return end
	local day = self:Today(char)
	local delta = newMoney - (oldMoney or newMoney)
	source = source or "other"
	if delta > 0 then
		day.earned = day.earned + delta
		day.income[source] = (day.income[source] or 0) + delta
	elseif delta < 0 then
		day.spent = day.spent - delta
		day.expense[source] = (day.expense[source] or 0) - delta
	end
	day.close = newMoney
	char.gold = newMoney
	char.lastSeen = GetServerTime()
end

-- Renvoie l'intervalle [fromDay, toDay] pour une période donnée.
function DB:GetPeriodRange(period)
	local today = self:DayId()
	if period == "day" then
		return today, today
	elseif period == "week" then
		return today - 6, today
	elseif period == "month" then
		return today - 29, today
	elseif period == "year" then
		return today - 364, today
	else -- "all"
		local first = today
		for _, char in pairs(OseilleDB.characters) do
			for dayId in pairs(char.days) do
				if dayId < first then first = dayId end
			end
		end
		return first, today
	end
end

-- Série du solde d'un personnage sur [fromDay, toDay], avec report (carry-forward)
-- du dernier solde connu pour les jours sans donnée.
-- Renvoie une table { {x = dayId, y = copper}, ... } triée par jour croissant.
function DB:GetCharSeries(charKey, fromDay, toDay)
	local char = OseilleDB.characters[charKey]
	if not char then return {} end
	return self:_BuildSeries(char.days, fromDay, toDay)
end

-- Série du patrimoine total (somme de tous les persos) sur [fromDay, toDay].
function DB:GetTotalSeries(fromDay, toDay)
	-- Pré-calcule la série reportée de chaque perso, puis somme jour par jour.
	local perChar = {}
	for key, char in pairs(OseilleDB.characters) do
		perChar[key] = self:_BuildBalanceLookup(char.days, fromDay, toDay)
	end

	local series = {}
	for dayId = fromDay, toDay do
		local total = 0
		for _, lookup in pairs(perChar) do
			total = total + (lookup[dayId] or 0)
		end
		series[#series + 1] = { x = dayId, y = total }
	end
	return series
end

-- Construit la table { [dayId] = solde reporté } pour un perso sur l'intervalle.
function DB:_BuildBalanceLookup(days, fromDay, toDay)
	-- Solde de départ = dernier close connu strictement avant fromDay.
	local last = 0
	local bestDay = nil
	for dayId in pairs(days) do
		if dayId < fromDay and (not bestDay or dayId > bestDay) then
			bestDay = dayId
		end
	end
	if bestDay then last = days[bestDay].close or 0 end

	local lookup = {}
	for dayId = fromDay, toDay do
		local day = days[dayId]
		if day then last = day.close or last end
		lookup[dayId] = last
	end
	return lookup
end

function DB:_BuildSeries(days, fromDay, toDay)
	local lookup = self:_BuildBalanceLookup(days, fromDay, toDay)
	local series = {}
	for dayId = fromDay, toDay do
		series[#series + 1] = { x = dayId, y = lookup[dayId] }
	end
	return series
end

-- Totaux gagné / dépensé / net cumulés sur la période.
-- charKey == nil ou "all" => agrège tous les personnages.
function DB:GetTotals(charKey, fromDay, toDay)
	local earned, spent = 0, 0
	local function add(char)
		for dayId = fromDay, toDay do
			local day = char.days[dayId]
			if day then
				earned = earned + (day.earned or 0)
				spent = spent + (day.spent or 0)
			end
		end
	end

	if charKey and charKey ~= "all" then
		local char = OseilleDB.characters[charKey]
		if char then add(char) end
	else
		for _, char in pairs(OseilleDB.characters) do
			add(char)
		end
	end
	return earned, spent, earned - spent
end

-- Totaux par source sur la période.
-- charKey == nil ou "all" => agrège tous les personnages.
-- Renvoie deux tables : income[source] = cuivre, expense[source] = cuivre.
-- Rétro-compat : les jours sans détail par source versent earned/spent dans "other".
function DB:GetSourceTotals(charKey, fromDay, toDay)
	local income, expense = {}, {}

	local function add(char)
		for dayId = fromDay, toDay do
			local day = char.days[dayId]
			if day then
				if day.income then
					for src, v in pairs(day.income) do
						income[src] = (income[src] or 0) + v
					end
				end
				if day.expense then
					for src, v in pairs(day.expense) do
						expense[src] = (expense[src] or 0) + v
					end
				end
				-- Données anciennes (pas de détail) : tout en "other".
				if not day.income and (day.earned or 0) > 0 then
					income.other = (income.other or 0) + day.earned
				end
				if not day.expense and (day.spent or 0) > 0 then
					expense.other = (expense.other or 0) + day.spent
				end
			end
		end
	end

	if charKey and charKey ~= "all" then
		local char = OseilleDB.characters[charKey]
		if char then add(char) end
	else
		for _, char in pairs(OseilleDB.characters) do
			add(char)
		end
	end
	return income, expense
end

-- Or total possédé actuellement (tous persos) ou pour un perso.
function DB:GetCurrentGold(charKey)
	if charKey and charKey ~= "all" then
		local char = OseilleDB.characters[charKey]
		return char and char.gold or 0
	end
	local total = 0
	for _, char in pairs(OseilleDB.characters) do
		total = total + (char.gold or 0)
	end
	return total
end

-- Liste triée des personnages : { {key, name, realm, class, gold}, ... }.
function DB:GetCharacterList()
	local list = {}
	for key, char in pairs(OseilleDB.characters) do
		list[#list + 1] = {
			key = key,
			name = char.name or key,
			realm = char.realm,
			class = char.class,
			gold = char.gold or 0,
		}
	end
	table.sort(list, function(a, b) return a.gold > b.gold end)
	return list
end
