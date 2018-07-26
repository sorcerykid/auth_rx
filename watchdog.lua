--------------------------------------------------------
-- Minetest :: Auth Redux Mod v2.9 (auth_rx)
--
-- See README.txt for licensing and release notes.
-- Copyright (c) 2017-2018, Leslie E. Krause
--------------------------------------------------------

----------------------------
-- AuthWatchdog Class
----------------------------

function AuthWatchdog( )
	local self = { }
	local clients = { }

	self.get_metadata = function ( ip )
		return clients[ ip ] or { }
	end
	self.on_failure = function ( ip )
		local meta = clients[ ip ]

		meta.count_failures = meta.count_failures + 1
		meta.newcheck = os.time( )
		if not meta.oldcheck then
			meta.oldcheck = os.time( )
		end

		return meta
	end
	self.on_success = function ( ip )
		clients[ ip ] = nil
	end
	self.on_attempt = function ( ip, name )
		if not clients[ ip ] then
			clients[ ip ] = { count_attempts = 0, count_failures = 0, previous_names = { } }
		end
		local meta = clients[ ip ]

		meta.count_attempts = meta.count_attempts + 1
		meta.prelogin = os.time( )
		table.insert( meta.previous_names, name )

		return meta
	end

	return self
end
