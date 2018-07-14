--------------------------------------------------------
-- Minetest :: Auth Redux Mod v2.4 (auth_rx)
--
-- See README.txt for licensing and release notes.
-- Copyright (c) 2017-2018, Leslie E. Krause
--------------------------------------------------------

----------------------------
-- Transaction Op Codes
----------------------------

local LOG_STARTED = 10			-- <timestamp> 10
local LOG_CHECKED = 11			-- <timestamp> 11
local LOG_STOPPED = 12			-- <timestamp> 12
local TX_CREATE = 20			-- <timestamp> 20 <username> <password>
local TX_DELETE = 21			-- <timestamp> 21 <username>
local TX_SET_PASSWORD = 40		-- <timestamp> 40 <username> <password>
local TX_SET_APPROVED_ADDRS = 41	-- <timestamp> 41 <username> <approved_addrs>
local TX_SET_ASSIGNED_PRIVS = 42	-- <timestamp> 42 <username> <assigned_privs>
local TX_SESSION_OPENED = 50		-- <timestamp> 50 <username>
local TX_SESSION_CLOSED = 51		-- <timestamp> 51 <username>
local TX_LOGIN_ATTEMPT = 30		-- <timestamp> 30 <username> <ip>
local TX_LOGIN_FAILURE = 31		-- <timestamp> 31 <username> <ip>
local TX_LOGIN_SUCCESS = 32		-- <timestamp> 32 <username>

----------------------------
-- Journal Class
----------------------------

function Journal( path, name, is_rollback )
	local file, err = io.open( path .. "/" .. name, "r+b" )
	local self = { }
	local cursor = 0
	local rtime = 1.0

	-- TODO: Verify integrity of database index
	if not file then
		minetest.log( "error", "Cannot open " .. path .. "/" .. name .. " for writing." )
		error( "Fatal exception in Journal( ), aborting." )
	end

	self.audit = function ( update_proc, is_rollback )
		-- Advance to the last set of noncommitted transactions (if any)
		if not is_rollback then
			minetest.log( "action", "Advancing database transaction log...." )
			for line in file:lines( ) do
				local fields = string.split( line, " ", true )

				if tonumber( fields[ 2 ] ) == LOG_STOPPED then
					cursor = file:seek( )
				end
			end
			file:seek( "set", cursor )
		end

		-- Update the database with all noncommitted transactions
		local meta = { }
		minetest.log( "action", "Replaying database transaction log...." )
		for line in file:lines( ) do
			local fields = string.split( line, " ", true )
			local optime = tonumber( fields[ 1 ] )
			local opcode = tonumber( fields[ 2 ] )

			update_proc( meta, optime, opcode, select( 3, unpack( fields ) ) )

			if opcode == LOG_CHECKED then
				-- Perform the commit and reset the log, if successful
				minetest.log( "action", "Resetting database transaction log..." )
				file:seek( "set", cursor )
				file:write( optime .. " " .. LOG_STOPPED .. "\n" )
				return optime
			end
			cursor = file:seek( )
		end
	end
	self.start = function ( )
		self.optime = os.time( )
		file:seek( "end", 0 )
		file:write( self.optime .. " " .. LOG_STARTED .. "\n" )
		cursor = file:seek( )
		file:write( self.optime .. " " .. LOG_CHECKED .. "\n" )
	end
	self.reset = function ( )
		file:seek( "set", cursor )
		file:write( self.optime .. " " .. LOG_STOPPED .. "\n" )
		self.optime = nil
	end
	self.record_raw = function ( opcode, ... )
		file:seek( "set", cursor )
		file:write( table.concat( { self.optime, opcode, ... }, " " ) .. "\n" )
		cursor = file:seek( )
		file:write( self.optime .. " " .. LOG_CHECKED .. "\n" )
	end
	minetest.register_globalstep( function( dtime )
		rtime = rtime - dtime
		if rtime <= 0.0 then
			if self.optime then
				-- touch file every 1.0 secs so we know if/when server crashes
				self.optime = os.time( )
				file:seek( "set", cursor )
				file:write( self.optime .. " " .. LOG_CHECKED .. "\n" )
			end
			rtime = 1.0
		end
	end )

	return self	
end

----------------------------
-- AuthDatabase Class
----------------------------

function AuthDatabase( path, name )
	local data, users, index
	local self = { }
	local journal = Journal( path, name .. "x" )

	-- Private methods

	local db_update = function( meta, optime, opcode, ... )
		local fields = { ... }

		if opcode == TX_CREATE then
			local rec = 
			{
				password = fields[ 2 ],
				oldlogin = -1,
				newlogin = -1,
				lifetime = 0,
				total_sessions = 0,
				total_attempts = 0,
				total_failures = 0,
				approved_addrs = { },
				assigned_privs = { },
			}
			data[ fields[ 1 ] ] = rec

		elseif opcode == TX_DELETE then
			data[ fields[ 1 ] ] = nil

		elseif opcode == TX_SET_PASSWORD then
			data[ fields[ 1 ] ].password = fields[ 2 ]

		elseif opcode == TX_SET_APPROVED_ADDRS then
			data[ fields[ 1 ] ].filered_addrs = string.split( fields[ 2 ], ",", true )

		elseif opcode == TX_SET_ASSIGNED_PRIVS then
			data[ fields[ 1 ] ].assigned_privs = string.split( fields[ 2 ], ",", true )

		elseif opcode == TX_LOGIN_ATTEMPT then
			data[ fields[ 1 ] ].total_attempts = data[ fields[ 1 ] ].total_attempts + 1

		elseif opcode == TX_LOGIN_FAILURE then
			data[ fields[ 1 ] ].total_failures = data[ fields[ 1 ] ].total_failures + 1

		elseif opcode == TX_LOGIN_SUCCESS then
			if data[ fields[ 1 ] ].oldlogin == -1 then
				data[ fields[ 1 ] ].oldlogin = optime
			end
			meta.users[ fields[ 1 ] ] = data[ fields[ 1 ] ].newlogin
			data[ fields[ 1 ] ].newlogin = optime

		elseif opcode == TX_SESSION_OPENED then
			data[ fields[ 1 ] ].total_sessions = data[ fields[ 1 ] ].total_sessions + 1

		elseif opcode == TX_SESSION_CLOSED then
			data[ fields[ 1 ] ].lifetime = data[ fields[ 1 ] ].lifetime + ( optime - data[ fields[ 1 ] ].newlogin )
			meta.users[ fields[ 1 ] ] = nil

		elseif opcode == LOG_STARTED then
			meta.users = { }

		elseif opcode == LOG_CHECKED or opcode == LOG_STOPPED then
			-- calculate leftover session lengths due to abnormal server termination
			for u, t in pairs( meta.users ) do
				data[ u ].lifetime = data[ u ].lifetime + ( optime - data[ u ].newlogin )
			end
			meta.users = nil
		end
	end

	local db_reload = function ( )
		minetest.log( "action", "Reading authentication data from disk..." )

		local file, errmsg = io.open( path .. "/" .. name, "r+b" )
		if not file then
			minetest.log( "error", "Cannot open " .. path .. "/" .. name .. " for reading." )
			error( "Fatal exception in AuthDatabase:db_reload( ), aborting." )
		end

		local head = assert( file:read( "*line" ) )

		index = tonumber( string.match( head, "^auth_rx/2.1 @(%d+)$" ) )
		if not index or index < 0 then
			minetest.log( "error", "Invalid header in authentication database." )
			error( "Fatal exception in AuthDatabase:reload( ), aborting." )
		end

		for line in file:lines( ) do
			if line ~= "" then
				local fields = string.split( line, ":", true )
				if #fields ~= 10 then
					minetest.log( "error", "Invalid record in authentication database." )
					error( "Fatal exception in AuthDatabase:reload( ), aborting." )
				end
				data[ fields[ 1 ] ] = {
					password = fields[ 2 ],
					oldlogin = tonumber( fields[ 3 ] ),
					newlogin = tonumber( fields[ 4 ] ),
					lifetime = tonumber( fields[ 5 ] ),
					total_sessions = tonumber( fields[ 6 ] ),
					total_attempts = tonumber( fields[ 7 ] ),
					total_failures = tonumber( fields[ 8 ] ),
					approved_addrs = string.split( fields[ 9 ], "," ),
					assigned_privs = string.split( fields[ 10 ], "," ),
				}
			end
		end
		file:close( )
	end

	local db_commit = function ( )
		minetest.log( "action", "Writing authentication data to disk..." )

		local file, errmsg = io.open( path .. "/~" .. name, "w+b" )
		if not file then
			minetest.log( "error", "Cannot open " .. path .. "/~" .. name .. " for writing." )
			error( "Fatal exception in AuthDatabase:db_commit( ), aborting." )
		end

		index = index + 1
		file:write( "auth_rx/2.1 @" .. index .. "\n" )

		for username, rec in pairs( data ) do
			assert( file:write( table.concat( {
				username,
				rec.password,
				rec.oldlogin,
				rec.newlogin,
				rec.lifetime,
				rec.total_sessions,
				rec.total_attempts,
				rec.total_failures,
				table.concat( rec.approved_addrs, "," ),
				table.concat( rec.assigned_privs, "," ),
			}, ":" ) .. "\n" ) )
		end
		file:close( )

		assert( os.remove( path .. "/" .. name ) )
		assert( os.rename( path .. "/~" .. name, path .. "/" .. name ) )
	end

	-- Public methods

	self.rollback = function ( )
		data = { }

		db_reload( )
		journal.audit( db_update, true )
		db_commit( )

		data = nil
	end

	self.connect = function ( )
		data = { }
		users = { }

		db_reload( )
		if journal.audit( db_update, false ) then
			db_commit( )
		end
		journal.start( )
	end

	self.disconnect = function ( )
		for u, t in pairs( users ) do
			data[ u ].lifetime = data[ u ].lifetime + ( journal.optime - data[ u ].newlogin )
		end

		db_commit( )
		journal.reset( )

		data = nil
		users = nil
	end

	self.create_record = function ( username, password )
		-- don't allow clobbering existing users
		if data[ username ] then return false end

		local rec =
		{
			password = password,
			oldlogin = -1,
			newlogin = -1,
			lifetime = 0,
			total_sessions = 0,
			total_attempts = 0,
			total_failures = 0,
			approved_addrs = { },
			assigned_privs = { },
		}
		data[ username ] = rec
		journal.record_raw( TX_CREATE, username, password )

		return true
	end

	self.delete_record = function ( username )
		-- don't allow deletion of online users or non-existent users
		if not data[ username ] or users[ username ] then return false end

		data[ username ] = nil
		journal.record_raw( TX_DELETE, username )

		return true
	end

	self.set_password = function ( username, password )
		if not data[ username ] then return false end

		data[ username ].password = password
		journal.record_raw( TX_SET_PASSWORD, username, password )
		return true
	end

	self.set_assigned_privs = function ( username, assigned_privs )
		if not data[ username ] then return false end

		data[ username ].assigned_privs = assigned_privs
		journal.record_raw( TX_SET_ASSIGNED_PRIVS, username, table.concat( assigned_privs, "," ) )
		return true
	end

	self.set_approved_addrs = function ( username, approved_addrs )
		if not data[ username ] then return false end

		data[ username ].approved_addrs = approved_addrs
		journal.record_raw( TX_SET_APPROVED_ADDRS, username, table.concat( approved_addrs, "," ) )
		return true
	end

	self.on_session_opened = function ( username )
		data[ username ].total_sessions = data[ username ].total_sessions + 1
		journal.record_raw( TX_SESSION_OPENED, username )
	end

	self.on_session_closed = function ( username )
		data[ username ].lifetime = data[ username ].lifetime + ( journal.optime - data[ username ].newlogin )
		users[ username ] = nil
		journal.record_raw( TX_SESSION_CLOSED, username )
	end

	self.on_login_attempt = function ( username, ip )
		data[ username ].total_attempts = data[ username ].total_attempts + 1
		journal.record_raw( TX_LOGIN_ATTEMPT, username, ip )
	end

	self.on_login_failure = function ( username, ip )
		data[ username ].total_failures = data[ username ].total_failures + 1
		journal.record_raw( TX_LOGIN_FAILURE, username, ip )
	end

	self.on_login_success = function ( username, ip )
		if data[ username ].oldlogin == -1 then
			data[ username ].oldlogin = journal.optime
		end
		users[ username ] = data[ username ].newlogin
		data[ username ].newlogin = journal.optime
		journal.record_raw( TX_LOGIN_SUCCESS, username, ip )
	end

	self.records = function ( )
		return pairs( data )
	end

	self.records_match = function ( pattern )
		local k
		return function ( )
			local v
			local p = string.lower( pattern )

			while true do
				k, v = next( data, k )
				if not k then
					return
				elseif string.match( string.lower( k ), p ) then
					return k, v
				end
			end
		end
	end

	self.select_record = function ( username )
		return data[ username ]
	end

	return self
end
