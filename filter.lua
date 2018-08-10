--------------------------------------------------------
-- Minetest :: Auth Redux Mod v2.12 (auth_rx)
--
-- See README.txt for licensing and release notes.
-- Copyright (c) 2017-2018, Leslie E. Krause
--------------------------------------------------------

FILTER_TYPE_STRING = 10
FILTER_TYPE_NUMBER = 11
FILTER_TYPE_ADDRESS = 12
FILTER_TYPE_BOOLEAN = 13
FILTER_TYPE_PATTERN = 14
FILTER_TYPE_SERIES = 15
FILTER_TYPE_PERIOD = 16
FILTER_TYPE_MOMENT = 17
FILTER_TYPE_DATESPEC = 18
FILTER_TYPE_TIMESPEC = 19
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
FILTER_COMP_IN = 55
FILTER_COMP_IS = 56
FILTER_COMP_HAS = 57

local decode_base64 = minetest.decode_base64
local encode_base64 = minetest.encode_base64
local trim = function ( str )
	return string.sub( str, 2, -2 )
end
local localtime = function ( str )
	-- daylight saving time is factored in automatically
	local x = { string.match( str, "^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)Z$" ) }
	return #x > 0 and os.time( { year = x[ 1 ], month = x[ 2 ], day = x[ 3 ], hour = x[ 4 ], min = x[ 5 ], sec = x[ 6 ] } ) or nil
end
local redate = function ( ts )
	-- convert to standard time (for timespec and datespec comparisons)
	local x = os.date( "*t", ts )
	x.isdst = false		
	return os.time( x )
end

----------------------------
-- StringPattern class
----------------------------

function StringPattern( phrase, is_mode, tokens )
	local glob = "^" .. string.gsub( phrase, ".", tokens ) .. "$"
	return { compare = function ( value, type )
		if not is_mode[ type ] then return end

		return string.find( value, glob ) == 1
	end }
end

----------------------------
-- NumberPattern class
----------------------------

function NumberPattern( phrase, is_mode, tokens, parser )
	local glob = { }
	local ref
	local find_token = function ( str, pat )
		ref = { string.match( str, pat ) }
		return #ref > 0
	end
	if #phrase ~= #tokens then
		return nil
	end
	for i, v in ipairs( phrase ) do
		local eval, args
		local t = tokens[ i ]
		if find_token( v, "^(" .. t .. ")$" ) then
			eval = function ( a, b ) return a == b end
			args = { tonumber( ref[ 1 ] ) }
		elseif find_token( v, "^(" .. t .. ")%^(" .. t .. ")$" ) then
			eval = function ( a, b, c ) return a >= b and a <= c end
			args = { tonumber( ref[ 1 ] ), tonumber( ref[ 2 ] ) }
		elseif find_token( v, "^(" .. t .. ")([<>])$" ) then
			eval = ref[ 2 ] == "<" and
				( function ( a, b ) return a <= b end ) or
				( function ( a, b ) return a >= b end )
			args = { tonumber( ref[ 1 ] ) }
		elseif v == "?" then
			eval = function ( ) return true end
			args = { }
		else
			return nil
		end
		table.insert( glob, { eval = eval, args = args } )
	end
	return { compare = function ( value, type )
		if not is_mode[ type ] then return end

		local fields = parser( value, type )
		for i, v in ipairs( glob ) do
			if not v.eval( fields[ i ], unpack( v.args ) ) then return false end
		end
		return true
	end }
end

----------------------------
-- AuthFilter class
----------------------------

function AuthFilter( path, name, debug )
	local src
	local is_active = true
	local self = { }

	local funcs = {
		["add"] = { type = FILTER_TYPE_NUMBER, args = { FILTER_TYPE_NUMBER, FILTER_TYPE_NUMBER }, def = function ( v, a, b ) return a + b end },
		["sub"] = { type = FILTER_TYPE_NUMBER, args = { FILTER_TYPE_NUMBER, FILTER_TYPE_NUMBER }, def = function ( v, a, b ) return a - b end },
		["mul"] = { type = FILTER_TYPE_NUMBER, args = { FILTER_TYPE_NUMBER, FILTER_TYPE_NUMBER }, def = function ( v, a, b ) return a * b end },
		["div"] = { type = FILTER_TYPE_NUMBER, args = { FILTER_TYPE_NUMBER, FILTER_TYPE_NUMBER }, def = function ( v, a, b ) return a / b end },
		["neg"] = { type = FILTER_TYPE_NUMBER, args = { FILTER_TYPE_NUMBER }, def = function ( v, a ) return -a end },
		["abs"] = { type = FILTER_TYPE_NUMBER, args = { FILTER_TYPE_NUMBER }, def = function ( v, a ) return math.abs( a ) end },
		["max"] = { type = FILTER_TYPE_NUMBER, args = { FILTER_TYPE_NUMBER, FILTER_TYPE_NUMBER }, def = function ( v, a, b ) return math.max( a, b ) end },
		["min"] = { type = FILTER_TYPE_NUMBER, args = { FILTER_TYPE_NUMBER, FILTER_TYPE_NUMBER }, def = function ( v, a, b ) return math.min( a, b ) end },
		["int"] = { type = FILTER_TYPE_NUMBER, args = { FILTER_TYPE_NUMBER }, def = function ( v, a ) return a < 0 and math.ceil( a ) or math.floor( a ) end },
		["num"] = { type = FILTER_TYPE_NUMBER, args = { FILTER_TYPE_STRING }, def = function ( v, a ) return tonumber( a ) or 0 end },
		["len"] = { type = FILTER_TYPE_NUMBER, args = { FILTER_TYPE_STRING }, def = function ( v, a ) return string.len( a ) end },
		["lc"] = { type = FILTER_TYPE_STRING, args = { FILTER_TYPE_STRING }, def = function ( v, a ) return string.lower( a ) end },
		["uc"] = { type = FILTER_TYPE_STRING, args = { FILTER_TYPE_STRING }, def = function ( v, a ) return string.upper( a ) end },
		["trim"] = { type = FILTER_TYPE_STRING, args = { FILTER_TYPE_STRING, FILTER_TYPE_NUMBER }, def = function ( v, a, b ) return b > 0 and string.sub( a, 1, -b - 1 ) or string.sub( a, -b + 1 ) end },
		["crop"] = { type = FILTER_TYPE_STRING, args = { FILTER_TYPE_STRING, FILTER_TYPE_NUMBER }, def = function ( v, a, b ) return b > 0 and string.sub( a, 1, b ) or string.sub( a, b, -1 ) end },
		["size"] = { type = FILTER_TYPE_NUMBER, args = { FILTER_TYPE_SERIES }, def = function ( v, a ) return #a end },
		["elem"] = { type = FILTER_TYPE_STRING, args = { FILTER_TYPE_SERIES, FILTER_TYPE_NUMBER }, def = function ( v, a, b ) return a[ b > 0 and b or #a + b + 1 ] or "" end },
		["split"] = { type = FILTER_TYPE_SERIES, args = { FILTER_TYPE_STRING, FILTER_TYPE_STRING }, def = function ( v, a, b ) return string.split( a, b, true ) end },
		["time"] = { type = FILTER_TYPE_TIMESPEC, args = { FILTER_TYPE_MOMENT }, def = function ( v, a ) return redate( a - v.epoch.value ) % 86400 end },
		["date"] = { type = FILTER_TYPE_DATESPEC, args = { FILTER_TYPE_MOMENT }, def = function ( v, a ) return math.floor( redate( a - v.epoch.value ) / 86400 ) end },
		["age"] = { type = FILTER_TYPE_PERIOD, args = { FILTER_TYPE_MOMENT }, def = function ( v, a ) return v.clock.value - a end },
		["before"] = { type = FILTER_TYPE_MOMENT, args = { FILTER_TYPE_MOMENT, FILTER_TYPE_PERIOD }, def = function ( v, a, b ) return a - b end },
		["after"] = { type = FILTER_TYPE_MOMENT, args = { FILTER_TYPE_MOMENT, FILTER_TYPE_PERIOD }, def = function ( v, a, b ) return a + b end },
		["day"] = { type = FILTER_TYPE_STRING, args = { FILTER_TYPE_MOMENT }, def = function ( v, a ) return os.date( "%a", a ) end },
		["at"] = { type = FILTER_TYPE_MOMENT, args = { FILTER_TYPE_STRING }, def = function ( v, a ) return localtime( a ) or 0 end },
		["ip"] = { type = FILTER_TYPE_STRING, args = { FILTER_TYPE_ADDRESS }, def = function ( v, a ) return table.concat( unpack_address( a ), "." ) end },
		["count"] = { type = FILTER_TYPE_NUMBER, args = { FILTER_TYPE_SERIES, FILTER_TYPE_STRING }, def = function ( v, a, b ) local t = 0; for i, v in ipairs( a ) do if v == b then t = t + 1; end; end; return t end },
		["clip"] = { type = FILTER_TYPE_SERIES, args = { FILTER_TYPE_SERIES, FILTER_TYPE_NUMBER }, def = function ( v, a, b ) local x = { }; local s = b < 0 and #a + b + 1 or 0; for i = 0, math.abs( b ) do table.insert( x, a[ s + i ] ); end; return x; end },
	}

	----------------------------
	-- private methods
	----------------------------

	local trace, get_operand, get_result, evaluate, tokenize

	trace = debug or function ( msg, num )
		minetest.log( "error", string.format( "%s (%s/%s, line %d)", msg, path, name, num ) )
		return num, "The server encountered an internal error."
	end

	function get_operand( token, vars )
		local t, v, ref

		local find_token = function ( pat )
			-- use back-references for easier conditional branching
			ref = { string.match( token, pat ) }
			return #ref > 0 and #ref
		end

		if find_token( "^(.-)([a-zA-Z0-9_]+)&([A-Za-z0-9+/]*);$" ) then
			local name = ref[ 2 ]
			local suffix = decode_base64( ref[ 3 ] )
			local prefix = ref[ 1 ]
			suffix = string.gsub( suffix, "%b()", function( str )
				-- encode nested function arguments
				return "&" .. encode_base64( trim( str ) ) .. ";"
			end )
			local args = string.split( suffix, ",", false )
			if string.match( prefix, "->$" ) then
				-- insert prefixed arguments
				table.insert( args, 1, string.sub( prefix, 1, -3 ) )
			elseif prefix ~= "" then
				return nil
			end
			if not funcs[ name ] or #funcs[ name ].args ~= #args then
				return nil
			end
			local params = { }
			for i, a in ipairs( args ) do
				local oper = get_operand( a, vars )
				if not oper or oper.type ~= funcs[ name ].args[ i ] then
					return nil
				end
				table.insert( params, oper.value )
			end
			t = funcs[ name ].type
			v = funcs[ name ].def( vars, unpack( params ) )
		elseif find_token( "^&([A-Za-z0-9+/]*);$" ) then
			t = FILTER_TYPE_SERIES
			v = { }
			local suffix = decode_base64( ref[ 1 ] )
			suffix = string.gsub( suffix, "%b()", function( str )
				-- encode nested function arguments
				return "&" .. encode_base64( trim( str ) ) .. ";"
			end )
			local elems = string.split( suffix, ",", false )
			for i, e in ipairs( elems ) do
				local oper = get_operand( e, vars )
				if not oper or oper.type ~= FILTER_TYPE_STRING then
					return nil
				end
				table.insert( v, oper.value )
			end
		elseif find_token( "^%$([a-zA-Z0-9_]+)$" ) then
			local name = ref[ 1 ]
			if not vars[ name ] or vars[ name ].value == nil then
				return nil
			end
			t = vars[ name ].type
			v = vars[ name ].value
		elseif find_token( "^@([a-zA-Z0-9_]+%.txt)$" ) then
			t = FILTER_TYPE_SERIES
			v = { }
			local file = io.open( path .. "/filters/" .. ref[ 1 ], "rb" )
			if not file then
				return nil
			end
			for line in file:lines( ) do
				table.insert( v, line )
			end
                elseif find_token( "^/([a-zA-Z0-9+/]*),([stda]);$" ) then
                        t = FILTER_TYPE_PATTERN
                        local phrase = minetest.decode_base64( ref[ 1 ] )
			if ref[ 2 ] == "s" then
				v = StringPattern( phrase, { [FILTER_TYPE_STRING] = true }, {
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
				} )
			elseif ref[ 2 ] == "t" then
				phrase = string.split( phrase, ":", false )
				v = NumberPattern( phrase, { [FILTER_TYPE_MOMENT] = true }, { "%d?%d", "%d%d", "%d%d" }, function ( value )
					-- direct translation (accounts for daylight saving time and time-zone offset)
					local timespec = os.date( "*t", value )
					return { timespec.hour, timespec.min, timespec.sec }
				end )
			elseif ref[ 2 ] == "d" then
				phrase = string.split( phrase, "-", false )
				v = NumberPattern( phrase, { [FILTER_TYPE_MOMENT] = true }, { "%d%d", "%d%d", "%d%d%d%d" }, function ( value )
					-- direct translation (accounts for daylight saving time and time-zone offset)
					local datespec = os.date( "*t", value )	
					return { datespec.day, datespec.month, datespec.year }
				end )
			elseif ref[ 2 ] == "a" then
				phrase = string.split( phrase, ".", false )
				v = NumberPattern( phrase, { [FILTER_TYPE_ADDRESS] = true }, { "%d?%d?%d", "%d?%d?%d", "%d?%d?%d", "%d?%d?%d" }, function ( value )
					return unpack_address( value )
				end )
			end
			if not v then
				return nil
			end
		elseif find_token( "^(%d+)([ywdhms])$" ) then
			local factor = { y = 31536000, w = 604800, d = 86400, h = 3600, m = 60, s = 1 }
			t = FILTER_TYPE_PERIOD
			v = tonumber( ref[ 1 ] ) * factor[ ref[ 2 ] ]
		elseif find_token( "^([-+]%d+)([ywdhms])$" ) then
			local factor = { y = 31536000, w = 604800, d = 86400, h = 3600, m = 60, s = 1 }
			local origin = string.byte( ref[ 1 ] ) == 45 and vars.clock.value or vars.epoch.value
			t = FILTER_TYPE_MOMENT
			v = origin + tonumber( ref[ 1 ] ) * factor[ ref[ 2 ] ]
		elseif find_token( "^(%d?%d):(%d%d):(%d%d)$" ) or find_token( "^(%d?%d):(%d%d)$" ) then
			local timespec = {
				isdst = false, day = 1, month = 1, year = 1970, hour = tonumber( ref[ 1 ] ), min = tonumber( ref[ 2 ] ), sec = ref[ 3 ] and tonumber( ref[ 3 ] ) or 0,
			}
			t = FILTER_TYPE_TIMESPEC
			v = ( os.time( timespec ) - vars.epoch.value ) % 86400			-- strip date component and time-zone offset (standardize time and account for overflow too)
		elseif find_token( "^(%d%d)%-(%d%d)%-(%d%d%d%d)$" ) then
			local datespec = {
				isdst = false, day = tonumber( ref[ 1 ] ), month = tonumber( ref[ 2 ] ), year = tonumber( ref[ 3 ] ), hour = 0,
			}
			t = FILTER_TYPE_DATESPEC
			v = math.floor( ( os.time( datespec ) - vars.epoch.value ) / 86400 )	-- strip time component and time-zone offset (standardize time too)
		elseif find_token( "^'([a-zA-Z0-9+/]*);$" ) then
			t = FILTER_TYPE_STRING
			v = decode_base64( ref[ 1 ] )
		elseif find_token( "^\"([a-zA-Z0-9+/]*);$" ) then
			t = FILTER_TYPE_STRING
			v = decode_base64( ref[ 1 ] )
			v = string.gsub( v, "%$([a-zA-Z_]+)", function ( var )
				return vars[ var ] and tostring( vars[ var ].value ) or "?"
			end )
		elseif find_token( "^-?%d+$" ) or find_token( "^-?%d*%.%d+$" ) then
			t = FILTER_TYPE_NUMBER
			v = tonumber( ref[ 1 ] )
		elseif find_token( "^(%d+)%.(%d+)%.(%d+)%.(%d+)$" ) then
			t = FILTER_TYPE_ADDRESS
			v = tonumber( ref[ 1 ] ) * 16777216 + tonumber( ref[ 2 ] ) * 65536 + tonumber( ref[ 3 ] ) * 256 + tonumber( ref[ 4 ] )
		else
			return nil
		end
		return { type = t, value = v }
	end

	function get_result( cond, comp, oper1, oper2 )
		-- only allow comparisons of appropriate and equivalent datatypes
		local do_math = { [FILTER_TYPE_NUMBER] = true, [FILTER_TYPE_PERIOD] = true, [FILTER_TYPE_MOMENT] = true, [FILTER_TYPE_DATESPEC] = true, [FILTER_TYPE_TIMESPEC] = true }
		local expr

		if comp == FILTER_COMP_EQ and oper1.type == oper2.type and oper1.type ~= FILTER_TYPE_SERIES and oper1.type ~= FILTER_TYPE_PATTERN then
			expr = ( oper1.value == oper2.value )
		elseif comp == FILTER_COMP_GT and oper1.type == oper2.type and do_math[ oper2.type ] then
			expr = ( oper1.value > oper2.value )
		elseif comp == FILTER_COMP_GTE and oper1.type == oper2.type and do_math[ oper2.type ] then
			expr = ( oper1.value >= oper2.value )
		elseif comp == FILTER_COMP_LT and oper1.type == oper2.type and do_math[ oper2.type ] then
			expr = ( oper1.value < oper2.value )
		elseif comp == FILTER_COMP_LTE and oper1.type == oper2.type and do_math[ oper2.type ] then
			expr = ( oper1.value <= oper2.value )
		elseif comp == FILTER_COMP_IS and oper1.type == FILTER_TYPE_STRING and oper2.type == FILTER_TYPE_STRING then
			expr = ( string.upper( oper1.value ) == string.upper( oper2.value ) )
		elseif comp == FILTER_COMP_IN and oper1.type == FILTER_TYPE_STRING and oper2.type == FILTER_TYPE_SERIES then
			local value1 = oper1.value
			expr = false
			for i, value2 in ipairs( oper2.value ) do
				expr = ( value1 == value2 )
				if expr then break end
			end
		elseif comp == FILTER_COMP_HAS and oper1.type == FILTER_TYPE_SERIES and oper2.type == FILTER_TYPE_STRING then
			local value2 = string.upper( oper2.value )
			expr = false
			for i, value1 in ipairs( oper1.value ) do
				expr = ( string.upper( value1 ) == value2 )
				if expr then break end
			end
		elseif comp == FILTER_COMP_HAS and oper1.type == FILTER_TYPE_SERIES and oper2.type == FILTER_TYPE_PATTERN then
			local compare = oper2.value.compare
			expr = false
			for i, value1 in ipairs( oper1.value ) do
				expr = compare( value1, FILTER_TYPE_STRING )
				if expr == nil then return end
				if expr then break end
			end
		elseif comp == FILTER_COMP_IS and oper2.type == FILTER_TYPE_PATTERN then
			expr = oper2.value.compare( oper1.value, oper1.type )
			if expr == nil then return end
		else
			return
		end
		if cond == FILTER_COND_FALSE then expr = not expr end

		return expr
	end

	function evaluate( rule )
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

	function tokenize( line )
		-- encode string and pattern literals and function arguments to simplify parsing (order IS significant)
		line = string.gsub( line, "\"(.-)\"", function ( str )
			return "\"" .. encode_base64( str ) .. ";"
		end )
		line = string.gsub( line, "'(.-)'", function ( str )
			return "'" .. encode_base64( str ) .. ";"
		end )
		line = string.gsub( line, "/(.-)/([stda]?)", function ( a, b )
			return "/" .. encode_base64( a ) .. "," .. ( b == "" and "s" or b ) .. ";"
		end )
		line = string.gsub( line, "%b()", function ( str )
			return "&" .. encode_base64( trim( str ) ) .. ";"
		end )
		return line
	end

	----------------------------
	-- public methods
	----------------------------

	self.translate = function ( field, vars )
		return get_operand( tokenize( field ), vars )
	end

	self.refresh = function ( )
		local file = io.open( path .. "/" .. name, "r" )
		if not file then
			error( "The specified ruleset file does not exist." )
		end
		src = { }
		for line in file:lines( ) do
			-- skip comments (lines beginning with hash character) and blank lines
			-- TODO: remove extraneous white space at beginning of lines
			table.insert( src, string.byte( line ) ~= 35 and tokenize( line ) or "" )
		end
		file:close( file )
	end

	self.add_preset_vars = function ( vars )
		vars[ "clock" ] = { type = FILTER_TYPE_MOMENT, value = os.time( ) }
		vars[ "epoch" ] = { type = FILTER_TYPE_MOMENT, value = os.time( { year = 1970, month = 1, day = 1, hour = 0 } ) }
		vars[ "true" ] = { type = FILTER_TYPE_BOOLEAN, value = true }
		vars[ "false" ] = { type = FILTER_TYPE_BOOLEAN, value = false }
	end

	self.process = function( vars )
		local rule
		local note = "Access denied."

		if not is_active then return end

		if not debug then
			-- allow overriding preset vars when debugger is active
			self.add_preset_vars( vars )
		end

		for num, line in ipairs( src ) do
			local stmt = string.split( line, " ", false )

			if #stmt == 0 then
				-- skip no-op statements

			elseif stmt[ 1 ] == "continue" then
				if not rule then return trace( "Unexpected 'continue' statement in ruleset", num ) end
				if #stmt ~= 1 then return trace( "Invalid 'continue' statement in ruleset", num ) end

				if evaluate( rule ) then
					return num, ( rule.mode == FILTER_MODE_FAIL and note or nil )
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
				if rule then return trace( "Missing 'continue' statement in ruleset", num ) end
				if #stmt ~= 2 then return trace( "Invalid 'pass' or 'fail' statement in ruleset", num ) end

				rule = { }

				local mode = ( { ["pass"] = FILTER_MODE_PASS, ["fail"] = FILTER_MODE_FAIL } )[ stmt[ 1 ] ]
				local bool = ( { ["all"] = FILTER_BOOL_AND, ["any"] = FILTER_BOOL_OR, ["one"] = FILTER_BOOL_XOR, ["now"] = FILTER_BOOL_NOW } )[ stmt[ 2 ] ]

				if not mode or not bool then
					return trace( "Unrecognized keywords in ruleset", num )
				end

				if bool == FILTER_BOOL_NOW then
					return num, ( mode == FILTER_MODE_FAIL and note or nil )
				end

				rule.mode = mode
				rule.bool = bool
				rule.expr = { }

			elseif stmt[ 1 ] == "when" or stmt[ 1 ] == "until" then
				if rule then return trace( "Unexpected 'when' or 'until' statement in ruleset", num ) end
				if #stmt ~= 5 then return trace( "Invalid 'when' or 'until' statement in ruleset", num ) end

				local mode = ( { ["pass"] = FILTER_MODE_PASS, ["fail"] = FILTER_MODE_FAIL } )[ stmt[ 5 ] ]
				local cond = ( { ["when"] = FILTER_COND_TRUE, ["until"] = FILTER_COND_FALSE } )[ stmt[ 1 ] ]
				local comp = ( { ["in"] = FILTER_COMP_IN, ["eq"] = FILTER_COMP_EQ, ["gt"] = FILTER_COMP_GT, ["lt"] = FILTER_COMP_LT, ["gte"] = FILTER_COMP_GTE, ["lte"] = FILTER_COMP_LTE, ["has"] = FILTER_COMP_HAS, ["is"] = FILTER_COMP_IS } )[ stmt[ 3 ] ]

				if not cond or not comp then
					return trace( "Unrecognized keywords in ruleset", num )
				end

				local oper1 = get_operand( stmt[ 2 ], vars )
				local oper2 = get_operand( stmt[ 4 ], vars )

				if not oper1 or not oper2 then
					return trace( "Unrecognized operands in ruleset", num )
				end

				local expr = get_result( cond, comp, oper1, oper2 )
				if expr == nil then
					return trace( "Mismatched operands in ruleset", num )
				elseif expr then
					return num, ( mode == FILTER_MODE_FAIL and note or nil )
				end

			elseif stmt[ 1 ] == "if" or stmt[ 1 ] == "unless" then
				if not rule then return trace( "Unexpected 'if' or 'unless' statement in ruleset", num ) end
				if #stmt ~= 4 then return trace( "Invalid 'if' or 'unless' statement in ruleset", num ) end

				local cond = ( { ["if"] = FILTER_COND_TRUE, ["unless"] = FILTER_COND_FALSE } )[ stmt[ 1 ] ]
				local comp = ( { ["in"] = FILTER_COMP_IN, ["eq"] = FILTER_COMP_EQ, ["gt"] = FILTER_COMP_GT, ["lt"] = FILTER_COMP_LT, ["gte"] = FILTER_COMP_GTE, ["lte"] = FILTER_COMP_LTE, ["has"] = FILTER_COMP_HAS, ["is"] = FILTER_COMP_IS } )[ stmt[ 3 ] ]

				if not cond or not comp then
					return trace( "Unrecognized keywords in ruleset", num )
				end

				local oper1 = get_operand( stmt[ 2 ], vars )
				local oper2 = get_operand( stmt[ 4 ], vars )

				if not oper1 or not oper2 then
					return trace( "Unrecognized operands in ruleset", num )
				end

				local expr = get_result( cond, comp, oper1, oper2 )
				if expr == nil then
					return trace( "Mismatched operands in ruleset", num )
				end

				table.insert( rule.expr, expr )
			else
				return trace( "Invalid statement in ruleset", num )
			end
		end
		return trace( "Unexpected end-of-file in ruleset", 0 )
	end

	self.enable = function ( )
		is_active = true
	end

	self.disable = function ( )
		is_active = false
	end

	self.is_active = function ( )
		return is_active
	end

	self.refresh( )

	return self
end
