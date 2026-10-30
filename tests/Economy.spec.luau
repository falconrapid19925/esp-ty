local Economy = require("../src/shared/Economy")
local Config = require("../src/shared/Config")
local NOW = 1793390400
local passed = 0

local function test(name, callback)
	local ok, err = pcall(callback)
	if not ok then error("FAIL " .. name .. ": " .. tostring(err), 0) end
	passed += 1
	print("PASS " .. name)
end

local function equal(actual, expected)
	assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

test("new cafe can earn its first useful upgrade from its first sale", function()
	local p = Economy.newProfile(NOW)
	assert(p.Cash < Economy.upgradeCost(p, "machine"))
	local income = Economy.recordSale(p, "espresso", true, false, false, NOW)
	assert(income > 0)
	assert(Economy.buyUpgrade(p, "machine", NOW))
	equal(p.Upgrades.machine, 1)
	equal(p.LifetimeServed, 1)
end)

test("locked recipes and unknown upgrades cannot mint or spend currency", function()
	local p = Economy.newProfile(NOW)
	local before = p.Cash
	equal(Economy.recordSale(p, "cold_brew", true, true, true, NOW), 0)
	equal(Economy.recordSale(p, "fake", true, true, true, NOW), 0)
	equal(Economy.buyUpgrade(p, "fake", NOW), false)
	equal(p.Cash, before)
	equal(p.LifetimeServed, 0)
end)

test("insufficient funds leave profile unchanged", function()
	local p = Economy.newProfile(NOW)
	equal(Economy.buyUpgrade(p, "staff", NOW), false)
	equal(p.Upgrades.staff, 0)
	equal(p.Cash, Config.StartingCash)
	equal(p.TotalUpgrades, 0)
end)

test("max upgrade cannot be bought again and costs increase", function()
	local p = Economy.newProfile(NOW)
	p.Cash = 1e8
	local previous = 0
	for _ = 1, Config.Upgrades[1].MaxLevel do
		local cost = Economy.upgradeCost(p, "machine")
		assert(cost > previous)
		previous = cost
		assert(Economy.buyUpgrade(p, "machine", NOW))
	end
	local before = p.Cash
	equal(Economy.upgradeCost(p, "machine"), nil)
	equal(Economy.buyUpgrade(p, "machine", NOW), false)
	equal(p.Cash, before)
end)

test("recipe unlock follows menu purchases and brew time stays positive", function()
	local p = Economy.newProfile(NOW)
	p.Cash = 1e8
	equal(#Economy.unlockedRecipes(p), 1)
	for level = 1, 5 do
		assert(Economy.buyUpgrade(p, "menu", NOW))
		equal(#Economy.unlockedRecipes(p), level + 1)
	end
	p.Upgrades.machine = 5
	for _, recipe in ipairs(Economy.unlockedRecipes(p)) do
		assert(Economy.brewDuration(p, recipe) >= 1.4)
		assert(Economy.brewDuration(p, recipe) < recipe.BrewTime)
	end
end)

test("service modifiers reward active skill without altering locked recipes", function()
	local p = Economy.newProfile(NOW)
	local recipe = Economy.recipe(p, "espresso")
	local regular = Economy.saleValue(p, recipe, false, false, false)
	local perfect = Economy.saleValue(p, recipe, true, false, false)
	assert(perfect > regular)
	assert(Economy.saleValue(p, recipe, true, true, true) > perfect)
	local income = Economy.recordSale(p, "espresso", true, true, false, NOW)
	equal(p.Cash, Config.StartingCash + income)
	equal(p.LifetimeEarned, income)
	equal(p.Daily.Earned, income)
	equal(p.PerfectShots, 1)
end)

test("daily rewards cannot be claimed early or replayed", function()
	local p = Economy.newProfile(NOW)
	local quest = Config.Quests[1]
	equal(Economy.claimQuest(p, quest.Id, NOW), false)
	p.Daily[quest.Metric] = quest.Target
	local before = p.Cash
	assert(Economy.claimQuest(p, quest.Id, NOW))
	equal(p.Cash, before + quest.Reward)
	equal(Economy.claimQuest(p, quest.Id, NOW), false)
	equal(p.Cash, before + quest.Reward)
end)

test("UTC daily rollover clears claims but leaves lifetime milestones", function()
	local p = Economy.newProfile(NOW)
	p.Daily.Served = 100
	p.Daily.Claimed.daily_serve = true
	p.Achievements.first_ten = true
	p.LifetimeServed = 100
	Economy.rollDaily(p, NOW + 86400)
	equal(p.Daily.Served, 0)
	equal(p.Daily.Claimed.daily_serve, nil)
	equal(p.LifetimeServed, 100)
	equal(p.Achievements.first_ten, true)
end)

test("milestone rewards are one-time and never recursively earn service goals", function()
	local p = Economy.newProfile(NOW)
	p.LifetimeServed = 10
	assert(Economy.claimAchievement(p, "first_ten"))
	equal(Economy.claimAchievement(p, "first_ten"), false)
	equal(p.Daily.Earned, 0)
	equal(p.LifetimeEarned, 0)
end)

test("offline income needs staff and has a hard four-hour cap", function()
	local p = Economy.newProfile(NOW)
	equal(Economy.offlineEarnings(p, 86400), 0)
	p.Upgrades.staff = 1
	equal(Economy.offlineEarnings(p, -100), 0)
	equal(Economy.offlineEarnings(p, 86400), Economy.offlineEarnings(p, Config.OfflineCapSeconds))
	assert(Economy.offlineEarnings(p, 3600) > 0)
	assert(Economy.offlineEarnings(p, 7200) > Economy.offlineEarnings(p, 3600))
	equal(p.Cash, Config.StartingCash)
end)

test("corrupt and hostile saved data is bounded and unknown keys discarded", function()
	local p = Economy.sanitize({
		Cash = 0 / 0, LifetimeEarned = math.huge, LifetimeServed = -50,
		Franchises = 1e20, LastSeen = NOW + 10000,
		Upgrades = { machine = 1000, menu = -20, staff = "three", fake = 999 },
		Theme = "nonexistent", Achievements = { fake = true, first_ten = "yes" },
		Daily = { Day = math.floor(NOW / 86400), Served = math.huge, Earned = -1, Claimed = { fake = true } },
	}, NOW)
	equal(p.Cash, Config.StartingCash)
	equal(p.LifetimeEarned, 0)
	equal(p.LifetimeServed, 0)
	equal(p.Franchises, 1000)
	equal(p.LastSeen, NOW)
	equal(p.Upgrades.machine, 5)
	equal(p.Upgrades.menu, 0)
	equal(p.Upgrades.staff, 0)
	equal(p.Upgrades.fake, nil)
	equal(p.Theme, "sage")
	equal(p.Achievements.fake, nil)
	equal(p.Achievements.first_ten, nil)
	equal(p.Daily.Served, 0)
end)

test("locked saved themes cannot skip franchise progression", function()
	equal(Economy.sanitize({ Theme = "midnight", Franchises = 0 }, NOW).Theme, "sage")
	equal(Economy.sanitize({ Theme = "midnight", Franchises = 2 }, NOW).Theme, "midnight")
end)

test("franchise is gated and preserves earned permanent progress", function()
	local p = Economy.newProfile(NOW)
	equal(Economy.franchise(p, NOW), false)
	p.Cash = Config.FranchiseCash
	equal(Economy.franchise(p, NOW), false)
	for id in pairs(p.Upgrades) do p.Upgrades[id] = 3 end
	p.Upgrades.expansion = 2
	p.TotalUpgrades = 40
	p.LifetimeServed = 200
	p.Achievements.first_ten = true
	assert(Economy.franchise(p, NOW))
	equal(p.Franchises, 1)
	equal(p.Cash, Config.StartingCash)
	equal(p.LifetimeServed, 200)
	equal(p.TotalUpgrades, 40)
	equal(p.Achievements.first_ten, true)
	for _, level in pairs(p.Upgrades) do equal(level, 0) end
	assert(Economy.setTheme(p, "terracotta"))
	equal(Economy.setTheme(p, "midnight"), false)
	assert(Economy.saleValue(p, Economy.recipe(p, "espresso"), false, false, false) > Config.Recipes[1].Price)
end)

test("saved profile roundtrip preserves earned progression and claim flags", function()
	local p = Economy.newProfile(NOW)
	p.Cash = 5000
	assert(Economy.buyUpgrade(p, "menu", NOW))
	for _ = 1, 20 do Economy.recordSale(p, "americano", true, false, false, NOW) end
	assert(Economy.claimQuest(p, "daily_serve", NOW))
	assert(Economy.claimAchievement(p, "first_ten"))
	local loaded = Economy.sanitize(p, NOW + 100)
	equal(loaded.Cash, p.Cash)
	equal(loaded.Upgrades.menu, 1)
	equal(loaded.PerfectShots, 20)
	equal(loaded.Daily.Claimed.daily_serve, true)
	equal(loaded.Achievements.first_ten, true)
end)

test("currency formatting stays readable across magnitudes", function()
	equal(Economy.formatMoney(0), "$0")
	equal(Economy.formatMoney(1234), "$1,234")
	equal(Economy.formatMoney(12500), "$12.5K")
	equal(Economy.formatMoney(1000000), "$1.00M")
end)

print(string.format("%d economy scenarios passed.", passed))
