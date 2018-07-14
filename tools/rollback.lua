--------------------------------------------------------
-- Minetest :: Auth Redux Mod v2.4 (auth_rx)
--
-- See README.txt for licensing and release notes.
-- Copyright (c) 2017-2018, Leslie E. Krause
--------------------------------------------------------

minetest = { }

function string.split( str, sep, has_nil )
	res = { }
	for val in string.gmatch( str .. sep, "(.-)" .. sep ) do
		if val ~= "" or has_nil then
			table.insert( res, val )
		end
	end
	return res
end

minetest.log = function ( act, str )
	print( "[" .. act .. "]", str )
end

minetest.register_globalstep = function ( ) end

--------------------------------------------------------

dofile( "../db.lua" )

local name = "auth.db"
local path = "."

print( "******************************************************" )
print( "* This script will rollback the Auth Redux database. *" )
print( "* Do not proceed unless you know what you are doing! *" )
print( "* -------------------------------------------------- *" )
print( "* Usage Example:                                     *" )
print( "* lua rollback.lua ~/.minetest/worlds/world/auth.db  *" )
print( "******************************************************" )

if arg[ 1 ] and arg[ 1 ] ~= "auth.db" then
	path = string.match( arg[ 1 ], "^(.*)/auth%.db$" )
	if not path then
		error( "Invalid arguments specified." )
	end
end

print( "The following database will be modified:" )
print( "  " .. path .. "/" .. name )
print( )

io.write( "Do you wish to continue (y/n)? " )
local opt = io.read( 1 )

if opt == "y" then
	print( "Initiating rollback procedure..." )

	local auth_db = AuthDatabase( path, name )
	auth_db.rollback( )

	os.rename( path .. "/" .. name .. "x", path .. "/~" .. name .. "x" )

	if not io.open( path .. "/" .. name .. "x", "w+b" ) then
		minetest.log( "error", "Cannot open " .. path .. "/~" .. name .. " for writing." )
	end
end
