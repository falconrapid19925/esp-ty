-- Pure deterministic economy. now is Unix seconds; Roblox services stay in GameService.
local Config = if script then require(script.Parent.Config) else require("./Config")
local Economy = {}
local MAX_NUMBER = 1e12

local function number(value, default, limit)
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return default
	end
	return math.clamp(math.floor(value), 0, limit or MAX_NUMBER)
end

local function find(list, id)
	for _, item in ipairs(list) do
		if item.Id == id then return item end
	end
	return nil
end

local function day(now)
	return math.floor(now / 86400)
end

local function credit(profile, amount)
	amount = number(amount, 0)
	profile.Cash = math.min(MAX_NUMBER, profile.Cash + amount)
	return amount
end

function Economy.newProfile(now)
	local upgrades = {}
	for _, upgrade in ipairs(Config.Upgrades) do upgrades[upgrade.Id] = 0 end
	return {
		Version = Config.Version, Cash = Config.StartingCash,
		LifetimeEarned = 0, LifetimeServed = 0, ManualServed = 0, PerfectShots = 0,
		TotalUpgrades = 0, Franchises = 0, Upgrades = upgrades, Theme = "sage",
		Daily = { Day = day(now), Served = 0, Earned = 0, Upgrades = 0, Claimed = {} },
		Achievements = {}, LastSeen = now,
	}
end

function Economy.rollDaily(profile, now)
	if type(profile.Daily) ~= "table" or profile.Daily.Day ~= day(now) then
		profile.Daily = { Day = day(now), Served = 0, Earned = 0, Upgrades = 0, Claimed = {} }
	end
end

function Economy.sanitize(raw, now)
	local profile = Economy.newProfile(now)
	if type(raw) ~= "table" then return profile end
	for _, key in ipairs({ "Cash", "LifetimeEarned", "LifetimeServed", "ManualServed", "PerfectShots", "TotalUpgrades", "Franchises", "LastSeen" }) do
		profile[key] = number(raw[key], profile[key], key == "Franchises" and 1000 or MAX_NUMBER)
	end
	profile.LastSeen = math.min(profile.LastSeen, now)
	if type(raw.Upgrades) == "table" then
		for _, upgrade in ipairs(Config.Upgrades) do
			profile.Upgrades[upgrade.Id] = number(raw.Upgrades[upgrade.Id], 0, upgrade.MaxLevel)
		end
	end
	local theme = find(Config.Themes, raw.Theme)
	if theme and profile.Franchises >= theme.RequiredFranchises then profile.Theme = theme.Id end
	if type(raw.Achievements) == "table" then
		for _, achievement in ipairs(Config.Achievements) do
			if raw.Achievements[achievement.Id] == true then profile.Achievements[achievement.Id] = true end
		end
	end
	if type(raw.Daily) == "table" and raw.Daily.Day == day(now) then
		for _, key in ipairs({ "Served", "Earned", "Upgrades" }) do
			profile.Daily[key] = number(raw.Daily[key], 0)
		end
		if type(raw.Daily.Claimed) == "table" then
			for _, quest in ipairs(Config.Quests) do
				if raw.Daily.Claimed[quest.Id] == true then profile.Daily.Claimed[quest.Id] = true end
			end
		end
	end
	return profile
end

function Economy.recipe(profile, id)
	local recipe = find(Config.Recipes, id)
	return recipe and recipe.MenuLevel <= profile.Upgrades.menu and recipe or nil
end

function Economy.unlockedRecipes(profile)
	local recipes = {}
	for _, recipe in ipairs(Config.Recipes) do
		if recipe.MenuLevel <= profile.Upgrades.menu then table.insert(recipes, recipe) end
	end
	return recipes
end

function Economy.upgradeCost(profile, id)
	local upgrade = find(Config.Upgrades, id)
	if not upgrade or profile.Upgrades[id] >= upgrade.MaxLevel then return nil end
	return math.floor(upgrade.BaseCost * upgrade.CostScale ^ profile.Upgrades[id] + 0.5)
end

function Economy.buyUpgrade(profile, id, now)
	Economy.rollDaily(profile, now)
	local cost = Economy.upgradeCost(profile, id)
	if not cost then return false, "This upgrade is unavailable or already complete." end
	if profile.Cash < cost then return false, "Serve a few more coffees to afford this upgrade." end
	profile.Cash -= cost
	profile.Upgrades[id] += 1
	profile.TotalUpgrades += 1
	profile.Daily.Upgrades += 1
	return true, find(Config.Upgrades, id).Name .. " upgraded!"
end

function Economy.brewDuration(profile, recipe)
	return math.max(1.4, recipe.BrewTime * (1 - 0.12 * profile.Upgrades.machine))
end

function Economy.saleValue(profile, recipe, perfect, vip, rush)
	local value = recipe.Price
		* (1 + profile.Upgrades.beans * 0.18)
		* (1 + profile.Upgrades.bakery * 0.08)
		* (1 + profile.Upgrades.decor * 0.05)
		* (1 + profile.Franchises * 0.20)
	if perfect then value *= 1.35 end
	if vip then value *= 1.6 end
	if rush then value *= 1.25 end
	return math.floor(value + 0.5)
end

function Economy.recordSale(profile, recipeId, perfect, vip, rush, now)
	local recipe = Economy.recipe(profile, recipeId)
	if not recipe then return 0 end
	Economy.rollDaily(profile, now)
	local amount = credit(profile, Economy.saleValue(profile, recipe, perfect, vip, rush))
	profile.LifetimeEarned = math.min(MAX_NUMBER, profile.LifetimeEarned + amount)
	profile.LifetimeServed += 1
	profile.Daily.Served += 1
	profile.Daily.Earned += amount
	if perfect then profile.PerfectShots += 1 end
	return amount
end

function Economy.staffInterval(profile)
	return math.max(3, 14 - profile.Upgrades.staff * 1.8 - profile.Upgrades.machine * 0.7 - profile.Upgrades.seating * 0.3)
end

function Economy.offlineEarnings(profile, seconds)
	if profile.Upgrades.staff <= 0 then return 0 end
	local recipes = Economy.unlockedRecipes(profile)
	local recipe = recipes[#recipes]
	local cycles = math.floor(math.clamp(seconds, 0, Config.OfflineCapSeconds) / Economy.staffInterval(profile))
	return math.floor(cycles * Economy.saleValue(profile, recipe, false, false, false) * Config.OfflineRate)
end

function Economy.claimQuest(profile, id, now)
	Economy.rollDaily(profile, now)
	local quest = find(Config.Quests, id)
	if not quest then return false, "Unknown daily goal." end
	if profile.Daily.Claimed[id] then return false, "You already claimed this daily goal." end
	if profile.Daily[quest.Metric] < quest.Target then return false, "Keep brewing to finish this goal." end
	profile.Daily.Claimed[id] = true
	credit(profile, quest.Reward)
	return true, "Daily goal complete! +$" .. tostring(quest.Reward)
end

function Economy.claimAchievement(profile, id)
	local achievement = find(Config.Achievements, id)
	if not achievement then return false, "Unknown milestone." end
	if profile.Achievements[id] then return false, "You already claimed this milestone." end
	if (profile[achievement.Metric] or 0) < achievement.Target then return false, "This milestone is still ahead of you." end
	profile.Achievements[id] = true
	credit(profile, achievement.Reward)
	return true, "Milestone reached! +$" .. tostring(achievement.Reward)
end

function Economy.canFranchise(profile)
	local upgrades = 0
	for _, level in pairs(profile.Upgrades) do upgrades += level end
	if profile.Cash < Config.FranchiseCash then return false, "Save $20,000 cash for your next chapter." end
	if upgrades < Config.FranchiseUpgrades then return false, "Buy at least 18 upgrades in this cafe first." end
	if profile.Upgrades.expansion < 2 then return false, "Complete both cafe expansions first." end
	return true, "Start a new cafe with +20% permanent service income. Styles unlock at franchises 1 and 2."
end

function Economy.franchise(profile, now)
	local allowed, message = Economy.canFranchise(profile)
	if not allowed then return false, message end
	profile.Franchises += 1
	profile.Cash = Config.StartingCash
	for id in pairs(profile.Upgrades) do profile.Upgrades[id] = 0 end
	profile.LastSeen = now
	return true, "New franchise opened! Permanent income bonus increased by 20%."
end

function Economy.setTheme(profile, id)
	local theme = find(Config.Themes, id)
	if not theme then return false, "Unknown cafe style." end
	if profile.Franchises < theme.RequiredFranchises then return false, "Open another franchise to unlock this style." end
	profile.Theme = id
	return true, theme.Name .. " applied."
end

function Economy.formatMoney(amount)
	amount = math.floor(math.max(0, amount))
	if amount >= 1e9 then return string.format("$%.2fB", amount / 1e9) end
	if amount >= 1e6 then return string.format("$%.2fM", amount / 1e6) end
	if amount >= 1e4 then return string.format("$%.1fK", amount / 1e3) end
	local text = tostring(amount)
	while true do
		local count
		text, count = string.gsub(text, "^(%d+)(%d%d%d)", "%1,%2")
		if count == 0 then break end
	end
	return "$" .. text
end

return Economy
