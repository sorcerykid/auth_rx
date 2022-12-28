--------------------------------------------------------
-- Minetest :: Auth Redux Mod v2.10 (auth_rx)
--
-- See README.txt for licensing and release notes.
-- Copyright (c) 2017-2018, Leslie E. Krause
--------------------------------------------------------

-----------------------------------------------------
-- Global Helper Functions
-----------------------------------------------------

get_minetest_config = function( key )
	minetest.settings:get( key )
end

function convert_ipv4( str )
	local ref = string.split( str, ".", false )
	return tonumber( ref[ 1 ] ) * 16777216 + tonumber( ref[ 2 ] ) * 65536 + tonumber( ref[ 3 ] ) * 256 + tonumber( ref[ 4 ] )
end

function unpack_address( addr )
        return { math.floor( addr / 16777216 ), math.floor( ( addr % 16777216 ) / 65536 ), math.floor( ( addr % 65536 ) / 256 ), addr % 256 }
end

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
