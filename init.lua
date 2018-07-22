--------------------------------------------------------
-- Minetest :: Auth Redux Mod v2.7 (auth_rx)
--
-- See README.txt for licensing and release notes.
-- Copyright (c) 2017-2018, Leslie E. Krause
--------------------------------------------------------

dofile( minetest.get_modpath( "auth_rx" ) .. "/filter.lua" )
dofile( minetest.get_modpath( "auth_rx" ) .. "/db.lua" )

-----------------------------------------------------
-- Registered Authentication Handler
-----------------------------------------------------

local auth_filter = AuthFilter( minetest.get_worldpath( ), "greenlist.mt" )
local auth_db = AuthDatabase( minetest.get_worldpath( ), "auth.db" )

local get_minetest_config = core.setting_get	-- backwards compatibility

function get_default_privs( )
	local default_privs = { }
	for _, p in pairs( string.split( get_minetest_config( "default_privs" ), "," ) ) do
		table.insert( default_privs, string.trim( p ) )
	end
	return default_privs
end

function unpack_privileges( assigned_privs )
	local privileges = { }
	for _, p in ipairs( assigned_privs ) do
		privileges[ p ] = true
	end
	return privileges
end

function pack_privileges( privileges )
	local assigned_privs = { }
	for p, _ in pairs( privileges ) do
		table.insert( assigned_privs, p )
	end
	return assigned_privs
end

if minetest.register_on_auth_fail then
	minetest.register_on_auth_fail( function ( player_name, player_ip )
		auth_db.on_login_failure( player_name, player_ip )
	end )
end

minetest.register_on_prejoinplayer( function ( player_name, player_ip )
	local rec = auth_db.select_record( player_name )

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

	local filter_err = auth_filter.process( {
		name = { type = FILTER_TYPE_STRING, value = player_name },
		addr = { type = FILTER_TYPE_STRING, value = player_ip },
		is_new = { type = FILTER_TYPE_BOOLEAN, value = rec == nil },
		privs_list = { type = FILTER_TYPE_SERIES, value = rec and rec.assigned_privs or { } },
		users_list = { type = FILTER_TYPE_SERIES, value = auth_db.search( true ) },
		cur_users = { type = FILTER_TYPE_NUMBER, value = #auth_db.search( true ) },
		max_users = { type = FILTER_TYPE_NUMBER, value = get_minetest_config( "max_users" ) },
		sessions = { type = FILTER_TYPE_NUMBER, value = rec and rec.total_sessions or 0 },
		failures = { type = FILTER_TYPE_NUMBER, value = rec and rec.total_failures or 0 },
		attempts = { type = FILTER_TYPE_NUMBER, value = rec and rec.total_attempts or 0 },
		owner = { type = FILTER_TYPE_STRING, value = get_minetest_config( "name" ) },
		uptime = { type = FILTER_TYPE_PERIOD, value = minetest.get_server_uptime( ) },
		oldlogin = { type = FILTER_TYPE_MOMENT, value = rec and rec.oldlogin or 0 },
		newlogin = { type = FILTER_TYPE_MOMENT, value = rec and rec.newlogin or 0 },
	} )

	return filter_err 
end )

minetest.register_on_joinplayer( function ( player )
	local player_name = player:get_player_name( )
	auth_db.on_login_success( player_name, "0.0.0.0" )
	auth_db.on_session_opened( player_name )
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

minetest.register_chatcommand( "filter", {
	description = "Enable or disable ruleset-based login filtering, or reload a ruleset definition.",
	privs = { server = true },
	func = function( name, param )
		if param == "" then
		return true, "Login filtering is currently " .. ( auth_filter.is_active( ) and "enabled" or "disabled" ) .. "."
		elseif param == "disable" then
			auth_filter.disable( )
			minetest.log( "action", "Login filtering disabled by " .. name .. "." )
			return true, "Login filtering is disabled."
		elseif param == "enable" then
			auth_filter.enable( )
			minetest.log( "action", "Login filtering enabled by " .. name .. "." )
			return true, "Login filtering is enabled."
		elseif param == "reload" then
			auth_filter.refresh( )
			return true, "Ruleset definition was loaded successfully."
		else
			return false, "Unknown parameter specified."
		end
	end
} )

auth_db.connect( )
