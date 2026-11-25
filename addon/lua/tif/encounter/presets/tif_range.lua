-- Base presets for tif_range (see mapsrc/make_tif_range.py for the layout).
-- Server only: included by TIF.Base.Presets(). Returns name -> definition.
--
-- The compound: walls x 700..3900, y -2900..300, gate on the north side (x 2080..2320), a side
-- door on the west wall (y ~ -1444), barracks x 1000..1800 / y -1100..-500 (two rooms),
-- HQ x 2600..3600 / y -2600..-1600, guard tower platform at x 3550..3750 / y 30..230, z 264.

return {
	compound = {
		name = "compound",
		faction = "insurgents",
		center = Vector(2300, -1300, 0),
		radius = 2000,
		posts = {
			-- Guards
			{ pos = Vector(3650, 130, 264), yaw = 125, job = "post", arch = "marksman" }, -- tower
			{ pos = Vector(2000, 80, 0), yaw = 90, job = "post", arch = "support" },    -- gate, behind sandbags
			{ pos = Vector(2400, 80, 0), yaw = 90, job = "post" },                      -- gate, behind sandbags
			{ pos = Vector(800, -1444, 0), yaw = 180, job = "post" },                   -- west side door
			{ pos = Vector(2550, -2368, 0), yaw = 180, job = "post" },                  -- HQ west door
			{ pos = Vector(2350, -1010, 0), yaw = 90, job = "post" },                   -- yard, by the crates
			-- Reserve in the barracks (west and east rooms)
			{ pos = Vector(1150, -700, 0), yaw = 0, job = "reserve", arch = "leader" },
			{ pos = Vector(1250, -900, 0), yaw = 90, job = "reserve" },
			{ pos = Vector(1150, -980, 0), yaw = 45, job = "reserve", arch = "assault" },
			{ pos = Vector(1550, -700, 0), yaw = 180, job = "reserve" },
			{ pos = Vector(1650, -870, 0), yaw = 90, job = "reserve", arch = "support" },
			{ pos = Vector(1550, -980, 0), yaw = 135, job = "reserve" },
		},
		routes = {
			-- Inside the walls, round the yard.
			{ size = 3, pts = {
				Vector(1000, -250, 0), Vector(3300, -250, 0), Vector(3300, -1350, 0), Vector(2300, -1350, 0),
				Vector(2300, -2750, 0), Vector(900, -2750, 0), Vector(900, -1300, 0),
			} },
			-- Outside the walls, along the roads.
			{ size = 3, pts = {
				Vector(600, 500, 0), Vector(4150, 500, 0), Vector(4150, -3150, 0), Vector(600, -3150, 0),
			} },
		},
		-- A vehicle patrol round the outer road loop (counter-clockwise from the north-west corner).
		vpatrols = {
			{ size = 4, pts = { -- (class nil: TIF.Mounted.DefaultCar(); was gtav_insurgent)
				Vector(-4190, 3190, 2), Vector(-4190, -3190, 2), Vector(4190, -3190, 2), Vector(4190, 3190, 2),
			} },
		},
		-- A two-car convoy round the ring road, the same way round as the vehicle patrol, starting
		-- mid-way along the south road (the column forms behind the first point, to the west).
		convoys = {
			-- (class nil: TIF.Mounted.DefaultCar(), an MW car from the TIF vehicle addon; was the GTA Baller)
			{ count = 2, size = 4, pts = {
				Vector(1500, -3190, 2), Vector(4190, -3190, 2), Vector(4190, 3190, 2), Vector(-4190, 3190, 2),
				Vector(-4190, -3190, 2),
			} },
		},
		-- Reinforcements come in from the south-east corner of the road loop.
		reinforce = { pos = Vector(4190, -3190, 2), size = 6 },
	},
}
