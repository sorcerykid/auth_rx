#!/bin/awk -f

################################################################################
# Database Export Script for Auth Redux Mod
# ------------------------------------------
# This script will revert to the default 'auth.txt' flat-file database required
# by the builtin authentication handler.
#
# EXAMPLE:
# awk -f revert.awk ~/.minetest/worlds/world/auth.db
################################################################################

BEGIN {
	FS = ":";
	OFS = ":";
	db_file = "auth.txt";

	path = ARGV[ 1 ]
	if( sub( /[-_A-Za-z0-9]+\.db$/, "", path ) == 0 ) {
		# sanity check for nonstandard input file
		path = "";
	}

	print "Reverting " ARGV[ 1 ] "...";
}

NF == 10 {
	username = $1;
	password = $2;
	assigned_privs = $10;
	newlogin = $4;

	print username, password, assigned_privs, newlogin > path db_file;
}

END {
	print "Done!"
}
