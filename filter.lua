--------------------------------------------------------
-- Minetest :: Auth Redux Mod v2.3 (auth_rx)
--
-- See README.txt for licensing and release notes.
-- Copyright (c) 2017-2018, Leslie E. Krause
--
-- ./games/minetest_game/mods/auth_rx/filter.lua
--------------------------------------------------------

FILTER_TYPE_STRING = 11
FILTER_TYPE_BOOLEAN = 12
FILTER_TYPE_NUMBER = 13
FILTER_TYPE_PATTERN = 14
FILTER_TYPE_SERIES = 15
FILTER_MODE_FAIL = 20
FILTER_MODE_PASS = 21
FILTER_BOOL_AND = 30
FILTER_BOOL_OR = 31
FILTER_BOOL_XOR = 32
FILTER_BOOL_NOW = 33
FILTER_COND_FALSE = 40
FILTER_COND_TRUE = 41
FILTER_COMP_EQ = 50
FILTER_COMP_GT = 51
FILTER_COMP_GTE = 52
FILTER_COMP_LT = 53
FILTER_COMP_LTE = 54
FILTER_COMP_IS = 55

----------------------------
-- AuthFilter class
----------------------------

function AuthFilter( path, name )
	local src = { }
	local opt = { is_debug = false, is_strict = true }
	local self = { }

	local file = io.open( path .. "/" .. name, "rb" )
	if not file then
		error( "The specified ruleset file does not exist." )
	end

	for line in file:lines( ) do
		-- encode string and pattern literals to make parsing easier
		line = string.gsub( line, "\"(.-)\"", function ( str )
			return "\"" .. minetest.encode_base64( str )
		end )
		line = string.gsub( line, "'(.-)'", function ( str )
			return "'" .. minetest.encode_base64( str )
		end )
		line = string.gsub( line, "/(.-)/", function ( str )
			return "/" .. minetest.encode_base64( str )
		end )

		table.insert( src, line )
	end

	file:close( file )

	----------------------------
	-- private methods
	----------------------------

	local trace = function ( msg, num )
		-- TODO: Use 'pcall' for more graceful exception handling?
		minetest.log( "error", string.format( "%s (%s/%s, line %d)", msg, path, name, num ) )
		return "The server encountered an internal error."
	end

	local get_operand = function ( token, vars )
		local t, v

		if string.find( token, "^%$[a-zA-Z_]+$" ) then
			local var = string.sub( token, 2 )
			if not vars[ var ] then
				return nil
			else
				t = vars[ var ].type
				v = vars[ var ].value
			end 
		elseif string.find( token, "^@[a-zA-Z0-9_]*%.txt$" ) then
			t = FILTER_TYPE_SERIES
			v = { }
			local file = io.open( path .. "/filters/" .. string.sub( token, 2 ), "rb" )
			if not file then
				return nil
			end
			for line in file:lines( ) do
				table.insert( v, line )
			end
		elseif string.find( token, "^/.*$" ) then
			-- sanitize search phrase and convert to regexp pattern
			local sanitizer =
			{
				["["] = "",
				["]"] = "",
				["^"] = "%^",
				["$"] = "%$",
				["("] = "%(",
				[")"] = "%)",
				["%"] = "%%",
				["-"] = "%-",
				[","] = "[a-z]",
				[";"] = "[A-Z]",
				["="] = "[-_]",
				["!"] = "[a-zA-Z0-9]",
				["*"] = "[a-zA-Z0-9_-]*",
				["+"] = "[a-zA-Z0-9_-]+",
				["?"] = "[a-zA-Z0-9_-]",
				["#"] = "%d",
				["&"] = "%a",
			}
			t = FILTER_TYPE_PATTERN
			v = minetest.decode_base64( string.sub( token, 2 ) )
			v = "^" .. string.gsub( v, ".", sanitizer ) .. "$"
		elseif string.find( token, "^'.*$" ) then
			t = FILTER_TYPE_STRING
			v = minetest.decode_base64( string.sub( token, 2 ) )
		elseif string.find( token, "^\".*$" ) then
			t = FILTER_TYPE_STRING
			v = minetest.decode_base64( string.sub( token, 2 ) )
			v = string.gsub( v, "%$([a-zA-Z_]+)", function ( var )
				return vars[ var ] and tostring( vars[ var ].value ) or "?"
			end )
		elseif string.find( token, "^-?%d+$" ) or string.find( token, "^-?%d*%.%d+$" ) then
			t = FILTER_TYPE_NUMBER
			v = tonumber( token )
		else
			return nil
		end
		return { type = t, value = v }
	end

	local evaluate = function ( rule )
		-- short circuit binary logic to simplify evaluation
		local res = ( rule.bool == FILTER_BOOL_AND )
		local xor = 0

		for i, v in ipairs( rule.expr ) do
			if rule.bool == FILTER_BOOL_AND and not v then
				return false
			elseif rule.bool == FILTER_BOOL_OR and v then
				return true
			elseif rule.bool == FILTER_BOOL_XOR and v then
				xor = xor + 1
			end
		end
		if xor == 1 then return true end

		return res
	end

	----------------------------
	-- public methods
	----------------------------

	self.process = function( vars )
		local rule
		local note = "Access denied."

		vars[ "true" ] = { type = FILTER_TYPE_BOOLEAN, value = true }
		vars[ "false" ] = { type = FILTER_TYPE_BOOLEAN, value = false }
		vars[ "time" ] = { type = FILTER_TYPE_NUMBER, value = os.time( ) }

		for num, line in ipairs( src ) do

			-- FIXME: ignore extraneous whitespace, even at beginning of line
			local stmt = string.split( line, " ", false )

			if string.byte( line ) == 35 or #stmt == 0 then
				-- skip comments (lines beginning with hash character) and empty lines
				-- TODO: these should be stripped on file import

			elseif stmt[ 1 ] == "continue" then
				if #stmt ~= 1 then return trace( "Invalid 'continue' statement in ruleset", num ) end

				if rule == nil then
					return trace( "No ruleset declared", num )
				end

				if evaluate( rule ) then
					return ( rule.mode == FILTER_MODE_FAIL and note or nil )
				end

				rule = nil

			elseif stmt[ 1 ] == "try" then
				if rule then return trace( "Missing 'continue' statement in ruleset", num ) end
				if #stmt ~= 2 then return trace( "Invalid 'try' statement in ruleset", num ) end

				local oper = get_operand( stmt[ 2 ], vars )
				if not oper or oper.type ~= FILTER_TYPE_STRING then
					return trace( "Unrecognized operand in ruleset", num )
				end

				note = oper.value

			elseif stmt[ 1 ] == "pass" or stmt[ 1 ] == "fail" then
				if rule then return trace( "Missing continue statement in ruleset", num ) end
				if #stmt ~= 2 then return trace( "Invalid 'pass' or 'fail' statement in ruleset", num ) end

				rule = { }

				local mode = ( { ["pass"] = FILTER_MODE_PASS, ["fail"] = FILTER_MODE_FAIL } )[ stmt[ 1 ] ]
				local bool = ( { ["all"] = FILTER_BOOL_AND, ["any"] = FILTER_BOOL_OR, ["one"] = FILTER_BOOL_XOR, ["now"] = FILTER_BOOL_NOW } )[ stmt[ 2 ] ]

				if not mode or not bool then
					return trace( "Unrecognized keywords in ruleset", num )
				end

				if bool == FILTER_BOOL_NOW then
					return ( mode == FILTER_MODE_FAIL and note or nil )
				end

				rule.mode = mode
				rule.bool = bool
				rule.expr = { }

			elseif stmt[ 1 ] == "when" or stmt[ 1 ] == "until" then
				if #stmt ~= 4 then return trace( "Invalid 'when' or 'until' statement in ruleset", num ) end

				local cond = ( { ["when"] = FILTER_COND_TRUE, ["until"] = FILTER_COND_FALSE } )[ stmt[ 1 ] ]
				local comp = ( { ["eq"] = FILTER_COMP_EQ, ["is"] = FILTER_COMP_IS } )[ stmt[ 3 ] ]

				if not cond or not comp then
					return trace( "Unrecognized keywords in ruleset", num )
				end

				local oper1 = get_operand( stmt[ 2 ], vars )
				local oper2 = get_operand( stmt[ 4 ], vars )

				if not oper1 or not oper2 then
					return trace( "Unrecognized operands in ruleset", num )
				elseif oper1.type ~= FILTER_TYPE_SERIES then
					return trace( "Mismatched operands in ruleset", num )
				end

				-- cache second operand value for efficiency
				-- TODO: might want to move the redundant operand type checks out of loop?

				local value2 = ( comp == FILTER_COMP_IS and oper2.type == FILTER_TYPE_STRING ) and string.upper( oper2.value ) or oper2.value
				local type2 = oper2.type
				local expr = false

				for i, value1 in ipairs( oper1.value ) do
					if comp == FILTER_COMP_EQ and type2 == FILTER_TYPE_STRING then
						expr = ( value1 == value2 )
					elseif comp == FILTER_COMP_IS and type2 == FILTER_TYPE_STRING then
						expr = ( string.upper( value1 ) == value2 )
					elseif comp == FILTER_COMP_IS and type2 == FILTER_TYPE_PATTERN then
						expr = ( string.find( value1, value2 ) == 1 )
					else
						return trace( "Mismatched operands in ruleset", num )
					end
					if expr then break end
				end
				if cond == FILTER_COND_FALSE then expr = not expr end

				table.insert( rule.expr, expr )

			elseif stmt[ 1 ] == "if" or stmt[ 1 ] == "unless" then
				if #stmt ~= 4 then return trace( "Invalid 'if' or 'unless' statement in ruleset", num ) end

				local cond = ( { ["if"] = FILTER_COND_TRUE, ["unless"] = FILTER_COND_FALSE } )[ stmt[ 1 ] ]
				local comp = ( { ["eq"] = FILTER_COMP_EQ, ["gt"] = FILTER_COMP_GT, ["lt"] = FILTER_COMP_LT, ["gte"] = FILTER_COMP_GTE, ["lte"] = FILTER_COMP_LTE, ["is"] = FILTER_COMP_IS } )[ stmt[ 3 ] ]

				if not cond or not comp then
					return trace( "Unrecognized keywords in ruleset", num )
				end

				local oper1 = get_operand( stmt[ 2 ], vars )
				local oper2 = get_operand( stmt[ 4 ], vars )

				if not oper1 or not oper2 then
					return trace( "Unrecognized operands in ruleset", num )
				end

				local expr
				if comp == FILTER_COMP_EQ and oper1.type == oper2.type and oper1.type ~= FILTER_TYPE_SERIES and oper1.type ~= FILTER_TYPE_PATTERN then
					expr = ( oper1.value == oper2.value )
				elseif comp == FILTER_COMP_IS and oper1.type == FILTER_TYPE_STRING and oper2.type == FILTER_TYPE_STRING then
					expr = ( string.upper( oper1.value ) == string.upper( oper2.value ) )
				elseif comp == FILTER_COMP_IS and oper1.type == FILTER_TYPE_STRING and oper2.type == FILTER_TYPE_PATTERN then
					expr = ( string.find( oper1.value, oper2.value ) == 1 )
				elseif comp == FILTER_COMP_GT and oper1.type == FILTER_TYPE_NUMBER and oper2.type == FILTER_TYPE_NUMBER then
					expr = ( oper1.value > oper2.value )
				elseif comp == FILTER_COMP_LT and oper1.type == FILTER_TYPE_NUMBER and oper2.type == FILTER_TYPE_NUMBER then
					expr = ( oper1.value < oper2.value )
				elseif comp == FILTER_COMP_GTE and oper1.type == FILTER_TYPE_NUMBER and oper2.type == FILTER_TYPE_NUMBER then
					expr = ( oper1.value >= oper2.value )
				elseif comp == FILTER_COMP_LTE and oper1.type == FILTER_TYPE_NUMBER and oper2.type == FILTER_TYPE_NUMBER then
					expr = ( oper1.value <= oper2.value )
				else
					return trace( "Mismatched operands in ruleset", num )
				end
				if cond == FILTER_COND_FALSE then expr = not expr end

				table.insert( rule.expr, expr )

				-- TODO: immediately evaluating each expression (thus avoiding a list) would be optimal,
				-- but probably requires state table; efficiency vs complexity scenario

			else
				return trace( "Invalid statement in ruleset", num )
			end
		end
		return trace( "Unexpected end-of-file in ruleset", 0 )
	end

	return self
end
