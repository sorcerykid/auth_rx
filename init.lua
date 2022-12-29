--------------------------------------------------------
-- Minetest :: Auth Redux Mod v2.13 (auth_rx)
--
-- See README.txt for licensing and release notes.
-- Copyright (c) 2017-2018, Leslie E. Krause
--------------------------------------------------------

local world_path = minetest.get_worldpath( )
local mod_path = minetest.get_modpath( "auth_rx" )

dofile( mod_path .. "/helpers.lua" )
dofile( mod_path .. "/filter.lua" )
dofile( mod_path .. "/db.lua" )
dofile( mod_path .. "/watchdog.lua" )
local __commands = dofile( mod_path .. "/commands.lua" )

-----------------------------------------------------
-- Registered Authentication Handler
-----------------------------------------------------

local auth_filter = AuthFilter( world_path, "greenlist.mt" )
local auth_db = AuthDatabase( world_path, "auth.db" )
local auth_watchdog = AuthWatchdog( )

if minetest.register_on_authplayer then
	minetest.register_on_authplayer( function ( player_name, player_ip, is_success )
		if is_success then
			return
		end
		auth_db.on_login_failure( player_name, player_ip )
		auth_watchdog.on_failure( convert_ipv4( player_ip ) )
	end )
elseif minetest.register_on_auth_fail then
	minetest.register_on_auth_fail( function ( player_name, player_ip )
		auth_db.on_login_failure( player_name, player_ip )
		auth_watchdog.on_failure( convert_ipv4( player_ip ) )
	end )
end

minetest.register_on_prejoinplayer( function ( player_name, player_ip )
	local rec = auth_db.select_record( player_name )
	local meta = auth_watchdog.get_metadata( convert_ipv4( player_ip ) )

	if rec then
		auth_db.on_login_attempt( player_name, player_ip )
	else
		-- prevent creation of case-insensitive duplicate accounts
		local uname = string.lower( player_name )
		for cname in auth_db.records( ) do
			if string.lower( cname ) == uname then
				return string.format( "A player named %s already exists on this server.", cname )
			end
		end
	end

	local res = auth_filter.is_enabled and auth_filter.process( {
		name = { type = FILTER_TYPE_STRING, value = player_name },
		addr = { type = FILTER_TYPE_ADDRESS, value = convert_ipv4( player_ip ) },
		is_new = { type = FILTER_TYPE_BOOLEAN, value = rec == nil },
		privs_list = { type = FILTER_TYPE_SERIES, value = rec and rec.assigned_privs or { } },
		users_list = { type = FILTER_TYPE_SERIES, value = auth_db.search( true ) },
		cur_users = { type = FILTER_TYPE_NUMBER, value = #auth_db.search( true ) },
		max_users = { type = FILTER_TYPE_NUMBER, value = get_minetest_config( "max_users" ) },
		lifetime = { type = FILTER_TYPE_PERIOD, value = rec and rec.lifetime or 0 },
		sessions = { type = FILTER_TYPE_NUMBER, value = rec and rec.total_sessions or 0 },
		failures = { type = FILTER_TYPE_NUMBER, value = rec and rec.total_failures or 0 },
		attempts = { type = FILTER_TYPE_NUMBER, value = rec and rec.total_attempts or 0 },
		owner = { type = FILTER_TYPE_STRING, value = get_minetest_config( "name" ) },
		uptime = { type = FILTER_TYPE_PERIOD, value = minetest.get_server_uptime( ) },
		oldlogin = { type = FILTER_TYPE_MOMENT, value = rec and rec.oldlogin or 0 },
		newlogin = { type = FILTER_TYPE_MOMENT, value = rec and rec.newlogin or 0 },
		ip_names_list = { type = FILTER_TYPE_SERIES, value = meta.previous_names or { } },
		ip_prelogin = { type = FILTER_TYPE_MOMENT, value = meta.prelogin or 0 },
		ip_oldcheck = { type = FILTER_TYPE_MOMENT, value = meta.oldcheck or 0 },
		ip_newcheck = { type = FILTER_TYPE_MOMENT, value = meta.newcheck or 0 },
		ip_failures = { type = FILTER_TYPE_NUMBER, value = meta.count_failures or 0 },
		ip_attempts = { type = FILTER_TYPE_NUMBER, value = meta.count_attempts or 0 }
	}, true ) or nil

	auth_watchdog.on_attempt( convert_ipv4( player_ip ), player_name )

	return res 
end )

minetest.register_on_joinplayer( function ( player )
	local player_name = player:get_player_name( )
	local player_ip =  minetest.get_player_information( player_name ).address	 -- this doesn't work in singleplayer!
	auth_db.on_login_success( player_name, player_ip )
	auth_db.on_session_opened( player_name )
	auth_watchdog.on_success( convert_ipv4( player_ip ) )
end )

minetest.register_on_leaveplayer( function ( player )
	auth_db.on_session_closed( player:get_player_name( ) )
end )

minetest.register_on_shutdown( function( )
	auth_db.disconnect( )
end )

minetest.register_authentication_handler( {
	-- translate old auth hooks to new database backend
	get_auth = function( username )
		local rec = auth_db.select_record( username )
		if rec then
			local assigned_privs = rec.assigned_privs

			if get_minetest_config( "name" ) == username then
				-- grant server operator all privileges
				-- (TODO: implement as function that honors give_to_admin flag)
				assigned_privs = { }
				for priv in pairs( core.registered_privileges ) do
					table.insert( assigned_privs, priv )
				end
			end

			return { password = rec.password, privileges = unpack_privileges( assigned_privs ), last_login = rec.newlogin }
		end
	end,
	create_auth = function( username, password )
		if auth_db.create_record( username, password ) then
			auth_db.set_assigned_privs( username, get_default_privs( ) )
			minetest.log( "info", "Created player '" .. username .. "' in authentication database" )
		end
	end,
	delete_auth = function( username )
		if auth_db.delete_record( username ) then
			minetest.log( "info", "Deleted player '" .. username .. "' in authenatication database" )
		end
	end,
	set_password = function ( username, password )
		if auth_db.set_password( username, password ) then
			minetest.log( "info", "Reset password of player '" .. username .. "' in authentication database" )
		end
	end,
	set_privileges = function ( username, privileges )
		-- server operator's privileges are immutable
		if get_minetest_config( "name" ) == username then return end

		if auth_db.set_assigned_privs( username, pack_privileges( privileges ) ) then
			minetest.notify_authentication_modified( username )
			minetest.log( "info", "Reset privileges of player '" .. username .. "' in authentication database" )
		end
	end,
	record_login = function ( ) end,
	reload = function ( ) end,
	iterate = auth_db.records
} )

auth_db.connect( )
auth_filter.is_enabled = true

__commands( { auth_db = auth_db, auth_filter = auth_filter } )

