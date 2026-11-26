return {
	compound = {
		name = "compound",
		faction = "insurgents",
		center = Vector(2300, -1300, 0),
		radius = 2000,
		posts = {

			{ pos = Vector(3650, 130, 264), yaw = 125, job = "post", arch = "marksman" },
			{ pos = Vector(2000, 80, 0), yaw = 90, job = "post", arch = "support" },
			{ pos = Vector(2400, 80, 0), yaw = 90, job = "post" },
			{ pos = Vector(800, -1444, 0), yaw = 180, job = "post" },
			{ pos = Vector(2550, -2368, 0), yaw = 180, job = "post" },
			{ pos = Vector(2350, -1010, 0), yaw = 90, job = "post" },

			{ pos = Vector(1150, -700, 0), yaw = 0, job = "reserve", arch = "leader" },
			{ pos = Vector(1250, -900, 0), yaw = 90, job = "reserve" },
			{ pos = Vector(1150, -980, 0), yaw = 45, job = "reserve", arch = "assault" },
			{ pos = Vector(1550, -700, 0), yaw = 180, job = "reserve" },
			{ pos = Vector(1650, -870, 0), yaw = 90, job = "reserve", arch = "support" },
			{ pos = Vector(1550, -980, 0), yaw = 135, job = "reserve" },
		},
		routes = {

			{ size = 3, pts = {
				Vector(1000, -250, 0), Vector(3300, -250, 0), Vector(3300, -1350, 0), Vector(2300, -1350, 0),
				Vector(2300, -2750, 0), Vector(900, -2750, 0), Vector(900, -1300, 0),
			} },

			{ size = 3, pts = {
				Vector(600, 500, 0), Vector(4150, 500, 0), Vector(4150, -3150, 0), Vector(600, -3150, 0),
			} },
		},

		vpatrols = {
			{ size = 4, pts = {
				Vector(-4190, 3190, 2), Vector(-4190, -3190, 2), Vector(4190, -3190, 2), Vector(4190, 3190, 2),
			} },
		},

		convoys = {

			{ count = 2, size = 4, pts = {
				Vector(1500, -3190, 2), Vector(4190, -3190, 2), Vector(4190, 3190, 2), Vector(-4190, 3190, 2),
				Vector(-4190, -3190, 2),
			} },
		},

		reinforce = { pos = Vector(4190, -3190, 2), size = 6 },
	},
}
