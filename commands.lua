--------------------------------------------------------
-- Minetest :: Auth Redux Mod v2.13 (auth_rx)
--
-- See README.txt for licensing and release notes.
-- Copyright (c) 2017-2018, Leslie E. Krause
--------------------------------------------------------

local auth_db, auth_filter		-- imported

minetest.register_chatcommand( "filter", {
	description = "Enable or disable ruleset-based login filtering, or reload a ruleset definition.",
	privs = { server = true },
	func = function( name, param )
		if param == "" then
		return true, "Login filtering is currently " .. ( auth_filter.is_enabled and "enabled" or "disabled" ) .. "."
		elseif param == "disable" then
			auth_filter.is_enabled = false
			minetest.log( "action", "Login filtering disabled by " .. name .. "." )
			return true, "Login filtering is disabled."
		elseif param == "enable" then
			auth_filter.is_enabled = true
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

minetest.register_chatcommand( "fdebug", {
	description = "Start an interactive debugger for testing ruleset definitions.",
	privs = { server = true },
	func = function( name, param )
		if not minetest.create_form then
			return false, "This feature is not supported."
		end

		local epoch = os.time( { year = 1970, month = 1, day = 1, hour = 0 } )
		local vars = {
			__debug = { type = FILTER_TYPE_NUMBER, value = 0 },
			name = { type = FILTER_TYPE_STRING, value = "singleplayer" },
			addr = { type = FILTER_TYPE_ADDRESS, value = convert_ipv4( "127.0.0.1" ) },
			is_new = { type = FILTER_TYPE_BOOLEAN, value = true },
			privs_list = { type = FILTER_TYPE_SERIES, value = { } },
			users_list = { type = FILTER_TYPE_SERIES, is_auto = true },
			cur_users = { type = FILTER_TYPE_NUMBER, is_auto = true },
			max_users = { type = FILTER_TYPE_NUMBER, value = get_minetest_config( "max_users" ) },
			lifetime = { type = FILTER_TYPE_PERIOD, value = 0 },
			sessions = { type = FILTER_TYPE_NUMBER, value = 0 },
			failures = { type = FILTER_TYPE_NUMBER, value = 0 },
			attempts = { type = FILTER_TYPE_NUMBER, value = 0 },
			owner = { type = FILTER_TYPE_STRING, value = get_minetest_config( "name" ) },
			uptime = { type = FILTER_TYPE_PERIOD, is_auto = true },
			oldlogin = { type = FILTER_TYPE_MOMENT, value = epoch },
			newlogin = { type = FILTER_TYPE_MOMENT, value = epoch },
			ip_names_list = { type = FILTER_TYPE_SERIES, value = { } },
			ip_prelogin = { type = FILTER_TYPE_MOMENT, value = epoch },
			ip_oldcheck = { type = FILTER_TYPE_MOMENT, value = epoch },
			ip_newcheck = { type = FILTER_TYPE_MOMENT, value = epoch },
			ip_failures = { type = FILTER_TYPE_NUMBER, value = 0 },
			ip_attempts = { type = FILTER_TYPE_NUMBER, value = 0 }
		}
		local vars_list = { "__debug", "clock", "name", "addr", "is_new", "privs_list", "users_list", "cur_users", "max_users", "lifetime", "sessions", "failures", "attempts", "owner", "uptime", "oldlogin", "newlogin", "ip_names_list", "ip_prelogin", "ip_oldcheck", "ip_newcheck", "ip_failures", "ip_attempts" }
		local datatypes = { [FILTER_TYPE_NUMBER] = "NUMBER", [FILTER_TYPE_STRING] = "STRING", [FILTER_TYPE_BOOLEAN] = "BOOLEAN", [FILTER_TYPE_ADDRESS] = "ADDRESS", [FILTER_TYPE_PERIOD] = "PERIOD", [FILTER_TYPE_MOMENT] = "MOMENT", [FILTER_TYPE_SERIES] = "SERIES" }
		local has_prompt = true
		local has_output = true
		local login_index = 2
		local var_index = 1
		local translate = GenericFilter( ).translate
		local temp_name = "~greenlist_" .. minetest.encode_base64( name ) .. ".mt"
		local temp_file = io.open( minetest.get_worldpath( ) .. "/" .. temp_name, "w" ):close( )
		local temp_filter = AuthFilter( minetest.get_worldpath( ), temp_name, function ( err, num )
			return "The server encountered an internal error.", num, err
		end )

		local function clear_prompts( buffer, has_single )
			-- clear debug prompts from source code
			return string.gsub( buffer, "\n# ====== .- ======\n", "\n", has_single and 1 or nil )
		end
		local function insert_prompt( buffer, num, err )
			-- insert debug prompts into source code
			local i = 0
			return string.gsub( buffer, "\n", function ( )
				i = i + 1
				return ( i == num and string.format( "\n# ====== ^ Line %d: %s ^ ======\n", num, err ) or "\n" )
			end )
		end
		local function format_value( value, type )
			-- convert values to a human-readable format
			if type == FILTER_TYPE_STRING then
				return "\"" .. value .. "\""
			elseif type == FILTER_TYPE_NUMBER then
				return tostring( value )
			elseif type == FILTER_TYPE_BOOLEAN then
				return "$" .. tostring( value )
			elseif type == FILTER_TYPE_PERIOD then
				return tostring( math.abs( value ) ) .. "s"
			elseif type == FILTER_TYPE_MOMENT then
				return "+" .. tostring( value - vars.epoch.value ) .. "s"
			elseif type == FILTER_TYPE_ADDRESS then
				return table.concat( unpack_address( value ), "." )
			elseif type == FILTER_TYPE_SERIES then
				return "(" .. string.gsub( table.concat( value, "," ), "[^,]+", "\"%1\"" ) .. ")"
			end
		end
		local function update_vars( )
			-- automatically update preset variables
			if vars.uptime.is_auto then
				vars.uptime.value = minetest.get_server_uptime( ) end
			if vars.clock.is_auto then
				vars.clock.value = os.time( ) end
			if vars.users_list.is_auto then
				vars.users_list.value = auth_db.search( true ) end
			if vars.cur_users.is_auto then
				vars.cur_users.value = #auth_db.search( true ) end
		end
		local function get_formspec( buffer, status, var_state )
			local var_name = vars_list[ var_index ]
			local var_type = vars[ var_name ].type
			local var_value = vars[ var_name ].value
			local var_is_auto = vars[ var_name ].is_auto

			local formspec = "size[13.5,8.5]"
				.. default.gui_bg
				.. default.gui_bg_img
				.. "label[0.1,0.0;Ruleset Definition:]"
				.. "checkbox[2.6,-0.2;has_output;Show Client Output;" .. tostring( has_output ) .. "]"
				.. "checkbox[5.6,-0.2;has_prompt;Show Debug Prompt;" .. tostring( has_prompt ) .. "]"
				.. "textarea[0.4,0.5;8.6," .. ( not status and "8.4" or status.user and "5.6" or "7.3" ) .. ";buffer;;" .. minetest.formspec_escape( buffer ) .. "]"
				.. "button[0.1,7.8;2,1;export_ruleset;Save]"
				.. "button[2.0,7.8;2,1;import_ruleset;Load]"
				.. "button[4.0,7.8;2,1;process_ruleset;Process]"
				.. "dropdown[6,7.9;2.6,1;login_mode;Normal,New Account,Wrong Password;" .. login_index .. "]"

				.. "label[9.0,0.0;Preset Variables:]"
				.. "textlist[9.0,0.5;4,4.7;vars_list"

			for i, v in pairs( vars_list ) do
				formspec = formspec .. ( i == 1 and ";" or "," ) .. minetest.formspec_escape( v .. " = " .. format_value( vars[ v ].value, vars[ v ].type ) )
			end
			formspec = formspec .. string.format( ";%d;false]", var_index )
				.. "label[9.0,5.4;Name:]"
				.. "label[9.0,5.9;Type:]"
				.. string.format( "label[10.5,5.4;%s]", minetest.colorize( "#BBFF77", "$" .. var_name ) )
				.. string.format( "label[10.5,5.9;%s]", datatypes[ var_type ] )
				.. "label[9.0,6.4;Value:]"
				.. "field[9.2,7.5;4.3,0.25;var_value;;" .. minetest.formspec_escape( format_value( var_value, var_type ) ) .. "]"
				.. "button[9.0,7.8;1,1;prev_var;<<]"
				.. "button[10.0,7.8;1,1;next_var;>>]"
				.. "button[11.8,7.8;1.5,1;set_var;Set]"

			if var_is_auto ~= nil then
				formspec = formspec .. "checkbox[10.5,6.2;var_is_auto;Auto Update;" .. tostring( var_is_auto ) .. "]"
			end

			if status then
				formspec = formspec .. "box[0.1,6.9;8.4,0.8;#555555]"
					.. "label[0.3,7.1;" .. minetest.colorize( status.type == "ERROR" and "#CCCC22" or "#22CC22", status.type .. ": " ) .. status.desc .. "]"
				if status.user then
					formspec = formspec .. "textlist[0.1,5.5;8.4,1.2;;Access denied. Reason: " .. minetest.formspec_escape( status.user ) .. ";0;false]"
				end
			end
			return formspec
		end
		local function on_close( meta, player, fields )
			login_index = ( { ["Normal"] = 1, ["New Account"] = 2, ["Wrong Password"] = 3 } )[ fields.login_mode ] or 1	-- sanity check

			if fields.quit then
				os.remove( minetest.get_worldpath( ) .. "/~greenlist.mt" )

			elseif fields.vars_list then
				local event = minetest.explode_textlist_event( fields.vars_list )
				if event.type == "CHG" then
					var_index = event.index
					minetest.update_form( name, get_formspec( fields.buffer ) )
				end

			elseif fields.has_prompt then
				has_prompt = fields.has_prompt == "true"

			elseif fields.has_output then
				has_output = fields.has_output == "true"

			elseif fields.export_ruleset then
				local buffer = clear_prompts( fields.buffer .. "\n", true )
				local file = io.open( minetest.get_worldpath( ) .. "/greenlist.mt", "w" )
				if not file then
					error( "Cannot write to ruleset definition file." )
				end
				file:write( buffer )
				file:close( )
				minetest.update_form( name, get_formspec( buffer, { type = "ACTION", desc = "Ruleset definition exported." } ) )

			elseif fields.import_ruleset then
				local file = io.open( minetest.get_worldpath( ) .. "/greenlist.mt", "r" )
				if not file then
					error( "Cannot read from ruleset definition file." )
				end
				minetest.update_form( name, get_formspec( file:read( "*a" ), { type = "ACTION", desc = "Ruleset definition imported." } ) )
				file:close( )

			elseif fields.process_ruleset then
				local status
				local buffer = clear_prompts( fields.buffer .. "\n", true )	-- we need a trailing newline, or things will break

				-- output ruleset to temp file for processing
				local temp_file = io.open( minetest.get_worldpath( ) .. "/" .. temp_name, "w" )
				temp_file:write( buffer )
				temp_file:close( )
				temp_filter.refresh( )

				update_vars( )

				if fields.login_mode == "New Account" then
					vars.is_new.value = true
					vars.privs_list.value = { }
					vars.lifetime.value = 0
					vars.sessions.value = 0
					vars.failures.value = 0
					vars.attempts.value = 0
					vars.newlogin.value = epoch
					vars.oldlogin.value = epoch
				else
					vars.is_new.value = false
					vars.attempts.value = vars.attempts.value + 1
				end

				-- process ruleset and benchmark performance
				local t = minetest.get_us_time( )
				local res, num, err = temp_filter.process( vars )
				t = ( minetest.get_us_time( ) - t ) / 1000

				if err then
					if has_prompt then buffer = insert_prompt( buffer, num, err ) end
					status = { type = "ERROR", desc = string.format( "%s (line %d).", err, num ), user = has_output and res }

					vars.ip_attempts.value = vars.ip_attempts.value + 1
					vars.ip_prelogin.value = vars.clock.value
					table.insert( vars.ip_names_list.value, vars.name.value )

				elseif res then
					if has_prompt then buffer = insert_prompt( buffer, num, "Ruleset failed" ) end
					status = { type = "ACTION", desc = string.format( "Ruleset failed at line %d (took %0.1f ms).", num, t ), user = has_output and res }

					vars.ip_attempts.value = vars.ip_attempts.value + 1
					vars.ip_prelogin.value = vars.clock.value
					table.insert( vars.ip_names_list.value, vars.name.value )

				elseif fields.login_mode == "Wrong Password" then
					if has_prompt then buffer = insert_prompt( buffer, num, "Ruleset failed" ) end
					status = { type = "ACTION", desc = string.format( "Ruleset passed at line %d (took %0.1f ms).", num, t ), user = has_output and "Invalid password" }

					vars.failures.value = vars.failures.value + 1
					vars.ip_attempts.value = vars.ip_attempts.value + 1
					vars.ip_failures.value = vars.ip_failures.value + 1
					vars.ip_prelogin.value = vars.clock.value
					vars.ip_newcheck.value = vars.clock.value
					if vars.ip_oldcheck.value == epoch then
						vars.ip_oldcheck.value = vars.clock.value
					end
					table.insert( vars.ip_names_list.value, vars.name.value )

				else
					if has_prompt then buffer = insert_prompt( buffer, num, "Ruleset passed" ) end
					status = { type = "ACTION", desc = string.format( "Ruleset passed at line %d (took %0.1f ms).", num, t ) }

					if fields.login_mode == "New Account" then
						vars.privs_list.value = get_default_privs( )
					end
					vars.sessions.value = vars.sessions.value + 1
					vars.newlogin.value = vars.clock.value
					if vars.oldlogin.value == epoch then 
						vars.oldlogin.value = vars.clock.value
					end
					vars.ip_failures.value = 0
					vars.ip_attempts.value = 0
					vars.ip_prelogin.value = epoch
					vars.ip_oldcheck.value = epoch
					vars.ip_newcheck.value = epoch
					vars.ip_names_list.value = { }
				end

				minetest.update_form( name, get_formspec( buffer, status ) )

			elseif fields.next_var or fields.prev_var then
				local idx = var_index
				local off = fields.next_var and 1 or -1
				if off == 1 and idx < #vars_list or off == -1 and idx > 1 then
					local v = vars_list[ idx ]
					vars_list[ idx ] = vars_list[ idx + off ]
					vars_list[ idx + off ] = v
					var_index = idx + off
					minetest.update_form( name, get_formspec( fields.buffer ) )
				end

			elseif fields.var_is_auto then
				local var_name = vars_list[ var_index ]
				vars[ var_name ].is_auto = ( fields.var_is_auto == "true" )

			elseif fields.set_var then
				local oper = translate( string.trim( fields.var_value ), vars )
				local var_name = vars_list[ var_index ]

				if oper and var_name == "__debug" and datatypes[ oper.type ] then
					-- debug variable can be any value/type
					vars.__debug = oper
				elseif oper and oper.type == vars[ var_name ].type then
					vars[ var_name ].value = oper.value
				end

				minetest.update_form( name, get_formspec( fields.buffer ) )

			end
		end

		temp_filter.add_preset_vars( vars )
		vars.clock.is_auto = true
		update_vars( )

		minetest.create_form( nil, name, get_formspec( "pass now\n" ), on_close )

		return true
	end,
} )

minetest.register_chatcommand( "auth", {
	description = "Open the authentication database management console.",
	privs = { server = true },
	func = function( name, param )
		local base_filter = GenericFilter( )
		local epoch = os.time( { year = 1970, month = 1, day = 1, hour = 0 } )
		local is_sort_reverse = false
		local vars_list = { "username", "password", "oldlogin", "newlogin", "lifetime", "total_sessions", "total_failures", "total_attempts", "assigned_privs" }
		local columns_list = { "$username", "$oldlogin->cal('D-MM-YY')", "$newlogin->cal('D-MM-YY')", "$lifetime->when('h')", "$total_sessions->str()", "$total_attempts->str()", "$total_failures->str()", "$assigned_privs->join(',')" }
		local results_list
		local selects_list
		local var_index = 1
		local var_input = ""
		local select_index
		local select_input = ""
		local result_index
		local results_horz
		local results_vert
		local column_index = 1
		local column_macro = ""

		base_filter.define_func( "str", FILTER_TYPE_STRING, { FILTER_TYPE_NUMBER },
			function ( v, a ) return tostring( a ) end )
		base_filter.define_func( "join", FILTER_TYPE_STRING, { FILTER_TYPE_SERIES, FILTER_TYPE_STRING },
			function ( v, a, b ) return table.concat( a, b ) end )
		base_filter.define_func( "when", FILTER_TYPE_STRING, { FILTER_TYPE_PERIOD, FILTER_TYPE_STRING },
			function ( v, a, b ) local f = { y = 31536000, w = 604800, d = 86400, h = 3600, m = 60, s = 1 }; return f[ b ] and ( math.floor( a / f[ b ] ) .. b ) or "?" end )
		base_filter.define_func( "cal", FILTER_TYPE_STRING, { FILTER_TYPE_MOMENT, FILTER_TYPE_STRING },
			function ( v, a, b ) local f = { ["Y"] = "%y", ["YY"] = "%Y", ["M"] = "%m", ["MM"] = "%b", ["D"] = "%d", ["DD"] = "%a", ["h"] = "%H", ["m"] = "%M", ["s"] = "%S" }; return os.date( string.gsub( b, "%a+", f ), a ) end )

		local function get_record_vars( username )
			local rec = auth_db.select_record( username )
			return rec and {
				username = { value = username, type = FILTER_TYPE_STRING },
				password = { value = rec.password, type = FILTER_TYPE_STRING },
				oldlogin = { value = rec.oldlogin, type = FILTER_TYPE_MOMENT },
				newlogin = { value = rec.newlogin, type = FILTER_TYPE_MOMENT },
				lifetime = { value = rec.lifetime, type = FILTER_TYPE_PERIOD },
				total_sessions = { value = rec.total_sessions, type = FILTER_TYPE_NUMBER },
				total_failures = { value = rec.total_failures, type = FILTER_TYPE_NUMBER },
				total_attempts = { value = rec.total_attempts, type  = FILTER_TYPE_NUMBER },
				assigned_privs = { value = rec.assigned_privs, type = FILTER_TYPE_SERIES },
			} or { username = { value = username, type = FILTER_TYPE_STRING } }
		end

		local function reset_results( )
			result_index = 1
			results_vert = 0
			results_horz = 0
			results_list = auth_db.search( false )
			select_index = 1
			selects_list = { { input = "(default)", cache = results_list } }
		end

		local function query_results( input )
			local stmt = string.split( base_filter.tokenize( input ), " ", false )
			if #stmt ~= 4 then
				return "Invalid 'if' or 'unless' statement in selector"
			end

			local cond = ( { ["if"] = FILTER_COND_TRUE, ["unless"] = FILTER_COND_FALSE } )[ stmt[ 1 ] ]
			local comp = ( { ["eq"] = FILTER_COMP_EQ, ["gt"] = FILTER_COMP_GT, ["lt"] = FILTER_COMP_LT, ["gte"] = FILTER_COMP_GTE, ["lte"] = FILTER_COMP_LTE, ["in"] = FILTER_COMP_IN, ["is"] = FILTER_COMP_IS, ["has"] = FILTER_COMP_HAS } )[ stmt[ 3 ] ]

			if not cond or not comp then
				return "Unrecognized keywords in selector"
			end

			-- initalize variables prior to loop (huge performance boost)
			local vars = {
				username = { type = FILTER_TYPE_STRING },
				password = { type = FILTER_TYPE_STRING },
				oldlogin = { type = FILTER_TYPE_MOMENT },
				newlogin = { type = FILTER_TYPE_MOMENT },
				lifetime = { type = FILTER_TYPE_PERIOD },
				total_sessions = { type = FILTER_TYPE_NUMBER },
				total_failures = { type = FILTER_TYPE_NUMBER },
				total_attempts = { type = FILTER_TYPE_NUMBER },
				assigned_privs = { type = FILTER_TYPE_SERIES },
			}
			base_filter.add_preset_vars( vars )

			local refs1, refs2, proc1, proc2, oper1, oper2
			local get_result = base_filter.get_result
			local get_operand_parser = base_filter.get_operand_parser
			local select_record = auth_db.select_record

			local res = { }
			for i, username in ipairs( results_list ) do
				local rec = select_record( username )

				if not rec then
					return "Attempt to index a non-existent record"
				end

				vars.username.value = username
				vars.password.value = rec.password
				vars.oldlogin.value = rec.oldlogin
				vars.newlogin.value = rec.newlogin
				vars.lifetime.value = rec.lifetime
				vars.total_sessions.value = rec.total_sessions
				vars.total_failures.value = rec.total_failures
				vars.total_attempts.value = rec.total_attempts
				vars.assigned_privs.value = rec.assigned_privs

				if not oper1 then
					-- get parser on first iteration
					if not proc1 then
						proc1, refs1 = get_operand_parser( stmt[ 2 ] )
					end
					oper1 = proc1 and proc1( refs1, vars )
				end
				if not oper2 then
					-- get parser on first iteration
					if not proc2 then
						proc2, refs2 = get_operand_parser( stmt[ 4 ] )
					end
					oper2 = proc2 and proc2( refs2, vars )
				end

				if not oper1 or not oper2 then
					return "Unrecognized operands in selector"
				end

				local expr = get_result( cond, comp, oper1, oper2 )

				if expr == nil then
					return "Mismatched operands in selector"
				end

				-- add matching records to results
				if expr then
					table.insert( res, username )
				end

				-- cache operands that are constant
				if not oper1.const then oper1 = nil end
				if not oper2.const then	oper2 = nil end
			end

			result_index = 1
			results_list = res
			results_vert = 0
			select_index = select_index + 1
			table.insert( selects_list, select_index, { input = input, cache = results_list } )
		end

		local function format_value( oper )
			if oper.type == FILTER_TYPE_STRING then
				return "\"" .. oper.value .. "\""
			elseif oper.type == FILTER_TYPE_NUMBER then
				return tostring( oper.value )
			elseif oper.type == FILTER_TYPE_MOMENT then
				return "+" .. tostring( math.max( 0, oper.value - epoch ) ) .. "s"
			elseif oper.type == FILTER_TYPE_PERIOD then
				return tostring( math.abs( oper.value ) ) .. "s"
			elseif oper.type == FILTER_TYPE_SERIES then
				return "(" .. string.gsub( table.concat( oper.value, "," ), "[^,]+", "\"%1\"" ) .. ")"
			end
		end

		local function get_escaped_fields( username )
			local fields = { }
			local vars = get_record_vars( username )
			base_filter.add_preset_vars( vars )

			for i = 1 + results_horz, #columns_list do
				local oper = base_filter.translate( columns_list[ i ], vars )
				table.insert( fields, minetest.formspec_escape(
					oper and oper.type == FILTER_TYPE_STRING and oper.value or "?" )
				)
			end
			return fields
		end

		local function sort_results( )
			local cache = { }
			local field = vars_list[ var_index ]
			local select_record = auth_db.select_record

			for i, v in ipairs( results_list ) do
				local rec = select_record( v )
				if rec then
					cache[ v ] = ( field == "username" and v or field == "assigned_privs" and #rec[ field ] or rec[ field ] )
				end
			end

			table.sort( results_list, function ( a, b )
				local value1, value2 = cache[ a ], cache[ b ]

				-- deleted records are lowest sort order
				if not value1 then return false end
				if not value2 then return true end

				if is_sort_reverse then
					return value1 > value2
				else
					return value1 < value2
				end
			end )

			result_index = 1
			results_vert = 0
		end

		local function get_formspec( err )
			local fs = minetest.formspec_escape
			local horz = ( #columns_list > 1 and ( 1000 / ( #columns_list - 1 ) * results_horz ) or 0 )
			local vert = ( #results_list > 1 and ( 1000 / ( #results_list - 1 ) * results_vert ) or 0 )
			local formspec = "size[13.5,9.0]"
				.. default.gui_bg
				.. default.gui_bg_img
				.. "label[0.1,0.0;Results (" .. #results_list .. " Records Selected):]"
				.. "checkbox[6.5,-0.2;is_sort_reverse;Reverse Sort;" .. tostring( is_sort_reverse ) .. "]"
				.. "tablecolumns[color" .. string.rep( ";text,width=10", #columns_list - results_horz ) .. "]"
				.. "table[0.1,0.5;8.6,7.3;results_list;#66DD66"

			for i = 1 + results_horz, #columns_list do
				formspec = formspec .. "," .. fs( string.sub( columns_list[ i ], 1, 18 ) )
			end
			for i = 1 + results_vert, math.min( #results_list, 15 + results_vert ) do
				formspec = formspec .. ",#FFFFFF," .. table.concat( get_escaped_fields( results_list[ i ] ), "," )
			end

			formspec = formspec .. ";" .. result_index .. "]"
				.. "scrollbar[0.1,7.8;8.6,0.4;horizontal;results_horz;" .. horz .. "]"
				.. "scrollbar[8.7,0.5;0.37,7.2;vertical;results_vert;" .. vert .. "]"

			if err then
				formspec = formspec .. "box[0.1,8.4;7.8,0.7;#555555]"
					.. "label[0.3,8.5;" .. minetest.colorize( "#CCCC22", "ERROR: " ) .. fs( err ) .. "]"
					.. "button[8.1,8.3;1.2,1;okay;Okay]"
			else
				formspec = formspec .. "dropdown[0.1,8.4;2.4,1;var_index;" .. table.concat( vars_list, "," ) .. ";" .. var_index .. "]"
					.. "field[2.8,9.0;3.7,0.25;var_input;;" .. fs( var_input ) .. "]"
					.. "button[6.1,8.3;1,1;set_records;Set]"
					.. "button[7.0,8.3;1,1;del_records;Del]"
					.. "button[8.1,8.3;1.2,1;sort_records;Sort]"
			end

			formspec = formspec .. "label[9.4,0.0;Columns:]"
				.. "textlist[9.4,0.5;2.9,2.7;columns_list"
			for i, v in ipairs( columns_list ) do
				formspec = formspec .. ( i == 1 and ";" or "," ) .. fs( v )
			end

			formspec = formspec .. ";" .. column_index .. ";false]"
				.. "button[12.4,0.4;1,1;prev_column;<<]"
				.. "button[12.4,1.2;1,1;next_column;>>]"
				.. "button[12.4,2.0;1,1;del_column;Del]"
				.. "button[12.4,3.2;1,1;add_column;Add]"
				.. "field[9.7,3.9;3.1,0.25;column_macro;;" .. fs( column_macro ) .. "]"

				.. "label[9.4,4.6;Selectors:]"
				.. "textlist[9.4,5.1;3.8,2.3;selects_list"
			for i, v in ipairs( selects_list ) do
				formspec = formspec .. ( i == 1 and ";" or "," ) .. fs( v.input )
			end

			formspec = formspec .. ";" .. select_index .. ";false]"
				.. "field[9.7,8.1;4.0,0.25;select_input;;" .. fs( select_input ) .. "]"
				.. "button[9.4,8.3;1.4,1;reset_results;Clear]"
				.. "button[12.0,8.3;1.4,1;query_results;Query]"

			return formspec
		end
		local function on_close( meta, player, fields )

			-- check single-operation elements first

			if fields.okay then
				minetest.update_form( name, get_formspec( ) )

			elseif fields.is_sort_reverse then
				is_sort_reverse = ( fields.is_sort_reverse == "true" )

			elseif fields.columns_list then
				local event = minetest.explode_textlist_event( fields.columns_list )
				if event.type == "CHG" then
					column_index = event.index
				elseif event.type == "DCL" then
					column_macro = columns_list[ column_index ]
					minetest.update_form( name, get_formspec( ) )
				end

			elseif fields.selects_list then
				local event = minetest.explode_textlist_event( fields.selects_list )
				if event.type == "CHG" then
					select_index = event.index
					results_list = selects_list[ event.index ].cache
					results_vert = 0
					minetest.update_form( name, get_formspec( ) )
				elseif event.type == "DCL" and select_index > 1 then
					select_input = selects_list[ event.index ].input
					minetest.update_form( name, get_formspec( ) )
				end

			elseif fields.results_list then
				local event = minetest.explode_table_event( fields.results_list )
				if event.type == "CHG" then
					result_index = event.row
				elseif event.type == "DCL" and result_index > 1 then
					local vars = get_record_vars( results_list[ results_vert + result_index - 1 ] )
					local oper = vars[ vars_list[ var_index ] ]
					var_input = oper and format_value( oper ) or ""
					minetest.update_form( name, get_formspec( ) )
				end

			elseif fields.next_column or fields.prev_column then
				local idx = column_index
				local off = fields.next_column and 1 or -1
				if off == 1 and idx < #columns_list or off == -1 and idx > 1 then
					local v = columns_list[ idx ]
					columns_list[ idx ] = columns_list[ idx + off ]
					columns_list[ idx + off ] = v
					column_index = idx + off
					minetest.update_form( name, get_formspec( ) )
				end

			elseif fields.del_column then
				if #columns_list > 1 then
					table.remove( columns_list, column_index )
					column_index = math.min( column_index, #columns_list )
					results_horz = 0
					minetest.update_form( name, get_formspec( ) )
				end

			elseif fields.add_column and fields.column_macro then
				if string.match( fields.column_macro, "%S+" ) and #columns_list < 10 then
					table.insert( columns_list, string.trim( fields.column_macro ) )
					column_macro = ""
					column_index = #columns_list
					minetest.update_form( name, get_formspec( ) )
				end

			elseif fields.del_records then
				local delete_record = auth_db.delete_record
				if result_index == 1 then
					for i, username in ipairs( results_list ) do
						delete_record( username )
					end
				else
					delete_record( results_list[ results_vert + result_index - 1 ] )
				end
				minetest.update_form( name, get_formspec( ) )

			elseif fields.sort_records then
				sort_results( )
				minetest.update_form( name, get_formspec( ) )

			elseif fields.query_results and fields.select_input then
				if string.match( fields.select_input, "%S+" ) and #selects_list < 5 then
					local input = string.trim( fields.select_input )
					local err = query_results( input )
					select_input = ( not err and "" or input )
					minetest.update_form( name, get_formspec( err ) )
				end

			elseif fields.reset_results then
				reset_results( )
				select_input = ""
				minetest.update_form( name, get_formspec( ) )

			-- check dual-operation elements last

			elseif fields.results_horz and fields.results_vert then

				local horz_event = minetest.explode_scrollbar_event( fields.results_horz )
				local vert_event = minetest.explode_scrollbar_event( fields.results_vert )

				if horz_event.type == "CHG" then
					local offset = horz_event.value - 1000 / ( #columns_list - 1 ) * results_horz

					if offset > 10 then
						results_horz = #columns_list - 1
					elseif offset < -10 then
						results_horz = 0
					elseif offset > 0 then
						results_horz = results_horz + 1
					elseif offset < 0 then
						results_horz = results_horz - 1
					end
					minetest.update_form( name, get_formspec( ) )

				elseif vert_event.type == "CHG" then
					-- TODO: Fix offset calculation to be more accurate?
					local offset = vert_event.value - 1000 / ( #results_list - 1 ) * results_vert

					if offset > 10 then
						results_vert = math.min( #results_list - 1, results_vert + 100 )
					elseif offset < -10 then
						results_vert =  math.max( 0, results_vert - 100 )
					elseif offset > 0 then
						results_vert = math.min( #results_list - 1, results_vert + 10 )
					elseif offset < 0 then
						results_vert = math.max( 0, results_vert - 10 )
					end
					result_index = 1
					minetest.update_form( name, get_formspec( ) )
				end

				var_index = ( { ["username"] = 1, ["password"] = 2, ["oldlogin"] = 3, ["newlogin"] = 4, ["lifetime"] = 5, ["total_sessions"] = 6, ["total_failures"] = 7, ["total_attempts"] = 8, ["assigned_privs"] = 9 } )[ fields.var_index ] or 1     -- sanity check
			end
                end

		reset_results( )
		minetest.create_form( nil, name, get_formspec( ), on_close )
	end,
} )

return function ( import )
	auth_db = import.auth_db
	auth_filter = import.auth_filter	
end
