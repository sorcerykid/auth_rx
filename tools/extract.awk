#!/bin/awk -f

################################################################################
# Database Import Script for Auth Redux Mod (Step 2)
# ---------------------------------------------------
# WARNING: This script is to be run immediately after the database conversion.
#
# This script will extract player login activity from the specified 'debug.txt'
# file and produce an import journal in the world directory. For best results,
# the 'auth.txt' and 'debug.txt' files should be complete and current. If they 
# are not entirely synchronous, then errors are likely to result.
#
# Lastly, run the rollback.lua script from the command line. This will replay
# the import journal against the newly converted database, applying all player
# login activity as it was derived from the corresponding debug log.
#
# Below is the required sequence of commands:
#
# > awk -f convert.awk -v mode=convert ~/.minetest/worlds/world/auth.txt
# > awk -f extract.awk ~/.minetest/worlds/world/auth.txt ~/.minetest/debug.txt
# > lua rollback.lua ~/.minetest/worlds/world/auth.db
#
# It is not necessary to operate on the original files. They can be moved into
# into a temporary subdirectory for use with all of these scripts.
#
# WARNING: The 'auth.dbx' file will be overwritten. This should not cause any
# problems if you began with a freshly converted database. When in doubt, then
# you may want to backup the 'auth.db' and 'auth.dbx' files as a precaution.
#
# For more detailed output, you can change the debug level as follows:
#
# > awk -f extract.awk -v debug=verbose ...
#
# This will display both errors and warnings. It might be helpful to redirect 
# output to a temporary file for this purpose. To see only errors, the default
# debug level of 'terse' should be sufficient.
#
# Warnings occur if there are orphaned accounts in the 'auth.txt' file that do 
# not appear in the corresponding debug log. This happens when the debug log
# is incomplete. Orphaned accounts will have no player login activity applied.
#
# Errors occur if the 'auth.txt' file is inconsistent with the debug log. This
# could be the result of a server crash or intentional deletion of accounts.
# Such accounts are deemed invalid and player login activity will be ignored.
# However, you should verify that you are using the correct 'auth.txt' file.
################################################################################

# USAGE EXAMPLE:
# awk -f extract.awk -v debug=terse /home/minetest/.minetest/worlds/world/auth.txt /home/minetest/.minetest/debug.txt

function get_timestamp( date_str, time_str ) {
	return mktime( sprintf( "%d %d %d %d %d %d", \
		substr( date_str, 1, 4 ), substr( date_str, 6, 2 ), substr( date_str, 9, 2 ), substr( time_str, 1, 2 ), substr( time_str, 4, 2 ), substr( time_str, 7, 2 ) ) );
}

function print_info( source, result ) {
	if( is_verbose == 1 ) {
		print "[" source "]", result;
	}
}

function check_user( name ) {
	if( name in db_users ) {
		++db_users[ name ];
		return 0;
	}

	if( !log_users[ name ] ) {
		print "ERROR: Player '" name "' does not exist in auth.txt file.";
	}
	return ++log_users[ name ];
}

function trim( str ) {
	return substr( str, 2, length( str ) - 2 )
}

BEGIN {
	FS = " "

	LOG_STARTED = 10
	LOG_STOPPED = 12
	LOG_TOUCHED = 13
	TX_SESSION_OPENED = 50
	TX_SESSION_CLOSED = 51
	TX_LOGIN_FAILURE = 31
	TX_LOGIN_SUCCESS = 32

	journal_file = "auth.dbx";
	is_started = 0;
	is_verbose = 0;

	total_records = 0;

	if( debug == "verbose" ) {
		is_verbose = 1;
	}
	else if( debug != "terse" ) {
                print "ERROR: Unknown argument, defaulting to terse debug level.";
	}

	if( ARGC != 3 ) {
		print( "The required arguments are missing, aborting." )
		exit 1;
	}

	world_path = ARGV[ 1 ];
	if( sub( /auth.txt$/, "", world_path ) == 0 ) {
		print( "The specified auth.txt file is not recognized, aborting." )
		exit 1;
	}

	if( ARGV[ 2 ] != "debug.txt" && ARGV[ 2 ] !~ /\/debug.txt$/ ) {
		print( "The specified debug.txt file is not recognized, aborting." )
		exit 1;
	}
}

# parse the 'auth.txt' file

ARGIND == 1 && FNR == 1 {
	print( "Reading the " world_path "auth.txt file..." )
}

ARGIND == 1 {
	name = substr( $0, 1, index( $0, ":" ) - 1 )
	db_users[ name ] = 0;
	total_records++;
}

# parse the 'debug.txt' file

ARGIND == 2 && FNR == 1 {
	print( "Reading the " world_path "debug.txt file..." )
}

ARGIND == 2 {
	cur_date_str = $1;
	cur_time_str = $2;

	if( $3 == "ACTION[Main]:" && ( $4 FS $5 ) == "World at" ) {

		# 2018-07-10 12:16:09: ACTION[Main]: World at [/root/.minetest/worlds/world]
		print_info( "debug.txt", $1 " @connect" );

		print get_timestamp( cur_date_str, cur_time_str ), LOG_STARTED > ( world_path journal_file );
		is_started = 1;
	}
	else if( !is_started ) {
		# sanity check since mod loading errors precede startup logging
		# and shutdowns are not always immediate after they are logged.
		next;
	}
	else if( $3 == "[Main]:" && $5 == "sigint_handler():" || $3 == "ERROR[Main]:" && ( $4 FS $5 ) == "stack traceback:" ) {

		# 2018-07-10 06:47:46: [Main]: INFO: sigint_handler(): Ctrl-C pressed, shutting down.
		# 2018-07-10 16:18:52: ERROR[Main]: stack traceback:
		print_info( "debug.txt", $1 " @disconnect " ( $4 == "stack" ? "(err)" : "(sig)" ) );

		print get_timestamp( cur_date_str, cur_time_str ), LOG_STOPPED > ( world_path journal_file );
		is_started = 0;
	}
	else if( $3 == "ACTION[Server]:" && ( $5 == "joins" || $6 == "joins" || $5 == "leaves" || $5 == "times" || $5 == "shuts" || $4 == "Server:" ) ) {	# optimization hack
		cur_action_str = substr( $0, 38 );

		if( cur_action_str ~ /^[a-zA-Z0-9_-]+ \[[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\] joins game\./ ) {

			# 2017-06-09 16:49:26: ACTION[Server]: sorcerykid [127.0.0.1] joins game.
#			print_info( "debug.txt", $1 " @on_login_success " $4 FS trim( $5 ) );

			if( check_user( $4 ) > 0 ) next;
			print get_timestamp( cur_date_str, cur_time_str ), TX_LOGIN_SUCCESS, $4, trim( $5 ) > ( world_path journal_file );
		}
		else if( cur_action_str ~ /^Server: User [a-zA-Z0-9_-]+ at [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ supplied wrong password/ ) {

			# 2017-06-09 20:35:20: ACTION[Server]: Server: User sorcerykid at 127.0.0.1 supplied wrong password (auth mechanism: SRP)
#			print_info( "debug.txt", $1 " @on_login_failure " $6 FS $8 );

			if( check_user( $6 ) > 0 ) next;
			print get_timestamp( cur_date_str, cur_time_str ), TX_LOGIN_FAILURE, $6, $8 > ( world_path journal_file );
		}
		else if( cur_action_str ~ /^[a-zA-Z0-9_-]+ joins game\./ ) {

			# 2017-06-09 16:49:26: ACTION[Server]: sorcerykid joins game. List of players: 
#			print_info( "debug.txt", $1 " @on_session_opened " $4 );

			if( check_user( $4 ) > 0 ) next;
			print get_timestamp( cur_date_str, cur_time_str ), TX_SESSION_OPENED, $4 > ( world_path journal_file );
		}
		else if( cur_action_str ~ /^[a-zA-Z0-9_-]+ leaves game\./ || cur_action_str ~ /[a-zA-Z0-9_-]+ times out\./ ) {

			# 2017-06-09 20:32:32: ACTION[Server]: sorcerykid leaves game. List of players: 
			# 2017-06-09 20:34:47: ACTION[Server]: sorcerykid times out. List of players: 
#			print_info( "debug.txt", $1 " @on_session_closed " $4 );

			if( check_user( $4 ) > 0 ) next;
			print get_timestamp( cur_date_str, cur_time_str ), TX_SESSION_CLOSED, $4 > ( world_path journal_file );
		}
		else if( cur_action_str ~ /^[a-zA-Z0-9_-]+ shuts down server/ ) {

			# 2017-06-09 20:32:32: ACTION[Server]: sorcerykid shuts down server
#			print_info( "debug.txt", $1 " @disconnect (req)" );

			print get_timestamp( cur_date_str, cur_time_str ), LOG_STOPPED > ( world_path journal_file );
			is_started = 0;
		}

	}
}

END {
	total_orphans = 0;
	for( name in db_users ) {
		if( db_users[ name ] == 0 ) {
			if( is_verbose == 1 ) {
				print "WARNING: No player activity for '" name "' in debug.txt file.";
			}
			total_orphans++;
		}
	}
	print "Total accounts in database: " total_records " (" total_orphans " orphaned accounts)";
	print "Done!"
}
