#!/bin/awk -f
# Database Import Script for Auth Redux (by Leslie Krause)
#
# STEP 1: Run this script from within the world directory and redirect output to "auth.db"
# awk -f auth.txt > auth.db
# STEP 2: Rename 'auth.txt' to 'auth.bak' or move to a different location for safekeeping

function error( msg ) {
	print( msg " at line " NR " in " FILENAME "." ) > "/dev/stderr"
}

BEGIN {
	FS = ":";

	# set default values for new database fields

	approved_addrs = "";
	oldlogin = -1;
	lifetime = 0;
	total_failures = 0;
	total_attempts = 0;
	total_sessions = 0;

	# output the database header
	# TODO: perhaps add? strftime( "%Y-%m-%d %H:%M:%S" )

	print "auth_rx/2.1 @0"
}

NF != 4 {
	error( "Malformed record" )
	next
}

{
	username = $1;
	password = $2;
	assigned_privs = $3;
	newlogin = $4;

	if( !match( username, "^[a-zA-Z0-9_-]+$" ) ) {
		error( "Invalid username field" )
		next
	}
	if( !match( newlogin, "^[0-9]+$" ) && newlogin != -1 ) {
		error( "Invalid last_login field" )
		next
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

	print( username ":" password ":" oldlogin ":" newlogin ":" lifetime ":" total_sessions ":" total_attempts ":" total_failures ":" approved_addrs ":" assigned_privs );
}
