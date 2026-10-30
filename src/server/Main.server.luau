-- World construction and reviewed asset loading are server-only.
local Assets = require(script.Parent.Assets)
local World = require(script.Parent.World)
local GameService = require(script.Parent.GameService)

Assets.preload()
local world = World.build()
GameService.start(world)
