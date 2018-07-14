#!/bin/awk -f

################################################################################
# Database Import Script for Auth Redux Mod
# ------------------------------------------
# This script will convert the specified 'auth.txt' file into a database format 
# required by the Auth Redux Mod. The output file will be generated in the same 
# world directory as the original 'auth.txt' file (which will be unchanged).
#
# Setting the mode to 'install' will automatically install the required journal
# and ruleset files into the world directory as well.
#
# EXAMPLE:
# awk -f convert.awk -v mode=convert ~/.minetest/worlds/world/auth.txt
################################################################################

function error( msg ) {
	skipped++;
	print msg " at line " NR " in " FILENAME ".";
}

BEGIN {
	FS = ":";
	OFS = ":";
	checked = 0;
	skipped = 0;

	db_file = "auth.db";
	journal_file = "auth.dbx";
	ruleset_file = "greenlist.mt";

	# determine output file name from arguments

	path = ARGV[ 1 ]
	if( sub( /[-_A-Za-z0-9]+\.txt$/, "", path ) == 0 ) {
		# sanity check for nonstandard input file
		path = "";
	}

	# install required journal and ruleset files

	if( mode == "install" ) {
		print "Installing the required journal and ruleset files...";
		print "" > path journal_file
		print "pass now" > path ruleset_file
	}		
	else if( mode != "convert" ) {
		print "Unknown argument, defaulting to convert mode.";
	}

	# set default values for new database fields

	approved_addrs = "";
	oldlogin = -1;
	lifetime = 0;
	total_failures = 0;
	total_attempts = 0;
	total_sessions = 0;

	# print database headline to the output file

	print "Converting " ARGV[ 1 ] "...";
	print "auth_rx/2.1 @0" > path db_file;
}

NF != 4 {
	error( "Malformed record" );
	next;
}

{
	username = $1;
	password = $2;
	assigned_privs = $3;
	newlogin = $4;

	if( !match( username, "^[a-zA-Z0-9_-]+$" ) ) {
		error( "Invalid username field" );
		next;
	}
	if( !match( newlogin, "^[0-9]+$" ) && newlogin != -1 ) {
		error( "Invalid last_login field" );
		next;
	}

	# Database File Format
	# --------------------
	# username
	# password
	# oldlogin
	# newlogin
	# lifetime
	# total_sessions
	# total_attempts
	# total_failures
	# approved_addrs
	# assigned_privs

	print username, password, oldlogin, newlogin, lifetime, total_sessions, total_attempts, total_failures, approved_addrs, assigned_privs > path db_file;

	checked++;
}

END {
	print "Done! " checked " of " ( checked + skipped ) " total records were imported to " db_file " (" skipped " records skipped)."
}
