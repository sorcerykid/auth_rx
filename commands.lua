--------------------------------------------------------
-- Minetest :: Auth Redux Mod v2.10 (auth_rx)
--
-- See README.txt for licensing and release notes.
-- Copyright (c) 2017-2018, Leslie E. Krause
--------------------------------------------------------

-----------------------------------------------------
-- Registered Chat Commands
-----------------------------------------------------

local auth_db, auth_filter		-- imported

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

minetest.register_chatcommand( "fdebug", {
	description = "Start an interactive debugger for testing ruleset definitions.",
	privs = { server = true },
	func = function( name, param )
		if not minetest.create_form then return false, "This feature is not supported." end

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
		local temp_file = io.open( minetest.get_worldpath( ) .. "/~greenlist.mt", "w" ):close( )
		local temp_filter = AuthFilter( minetest.get_worldpath( ), "~greenlist.mt", function ( err, num )
			return num, "The server encountered an internal error.", err
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
				local temp_file = io.open( minetest.get_worldpath( ) .. "/~greenlist.mt", "w" )
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
				local num, res, err = temp_filter.process( vars )
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
					status = { type = "ACTION", desc = string.format( "Ruleset failed at line %d (took %0.1f ms).", num, t ), user = has_output and "Invalid password" }

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
				local oper = temp_filter.translate( string.trim( fields.var_value ), vars )
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

return function ( import )
	auth_db = import.auth_db
	auth_filter = import.auth_filter	
end
