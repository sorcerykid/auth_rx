#!/bin/awk -f
########################################################
#                                                      #
#  Minetest :: Auth Redux Mod v2.11 (auth_rx)          #
#                                                      #
#  See README.txt for licensing and release notes.     #
#  Copyright (c) 2017-2018, Leslie E. Krause           #
#                                                      #
########################################################

# Run this script and optionally redirect output to a text file
# awk -f report.awk -v days=1 type=txt ~/.minetest/worlds/world/auth.dbx

function throw( msg ) {
	print msg > "/dev/tty";
	status = 1;
	exit 1;
}

function get_period( t ) {
	return int( ( t - rel_time ) / 3600 )
}

function on_server_startup( cur_time ) {
	server_start = cur_time
}

function on_server_shutdown( cur_time, _old_time, _new_time ) {
	_old_time = server_start < rel_time ? rel_time : server_start;
	_new_time = cur_time >= rel_time + 86400 ? rel_time + 86399 : cur_time;
	server_uptime = server_uptime + ( _new_time - _old_time );
	server_start = NIL;
}

function on_login_failure( cur_time ) {
	hourly_failures[ get_period( cur_time ) ]++;
	total_failures++;
}

function on_login_attempt( cur_time ) {
	hourly_attempts[ get_period( cur_time ) ]++;
	total_attempts++;
}
function on_create( cur_time, cur_user ) {
	player_is_new[ cur_user ] = 1;
}

function on_session_opened( cur_time, cur_user ) {
	while( cur_period < get_period( cur_time ) ) {
		if( hourly_players[ cur_period ] == NIL ) {
			# initialize client and player stats in prior periods
			hourly_clients_max[ cur_period ] = cur_clients;
			hourly_clients_min[ cur_period ] = cur_clients;
			hourly_players[ cur_period ] = cur_clients;
		}
		cur_period++;
	}

	if( hourly_players[ cur_period ] == NIL ) {
		# initialize client and player stats for this period
		hourly_clients_max[ cur_period ] = cur_clients + 1;
		hourly_clients_min[ cur_period ] = cur_clients;
		hourly_players[ cur_period ] = cur_clients;
		delete player_check;
	}
	else if( cur_clients + 1 > hourly_clients_max[ cur_period ] ) {
		# update client stats for this period, if needed
		hourly_clients_max[ cur_period ] = cur_clients + 1;
	}
	if( player_check[ cur_user ] == NIL ) {
		# track another unique player
		player_check[ cur_user ] = 1;
		hourly_players[ cur_period ]++;
	}

	# update some general stats
	if( player_is_new[ cur_user ] == 1 ) {
		# only count new players after joining game (sanity check)
		player_is_new[ cur_user ] = -1;
		total_players_new++;
	}
	if( max_clients == NIL || cur_clients + 1 > max_clients ) {
		max_clients = cur_clients + 1;
	}
	if( min_clients == NIL || cur_clients < min_clients ) {
		min_clients = cur_clients;
	}
}

function on_session_closed( cur_time, cur_user, _old_time, _new_time ) {
	_old_time = player_login[ cur_user ] < rel_time ? rel_time : player_login[ cur_user ];
	_new_time = cur_time >= rel_time + 86400 ? rel_time + 86399 : cur_time;
	lifetime = _new_time - _old_time;

	while( cur_period < get_period( _new_time ) ) {
		if( hourly_players[ cur_period ] == NIL ) {
			# initialize client and player stats in prior periods
			hourly_clients_max[ cur_period ] = cur_clients;
			hourly_clients_min[ cur_period ] = cur_clients;
			hourly_players[ cur_period ] = cur_clients;
		}
		cur_period++;
	}

	if( hourly_players[ cur_period ] == NIL ) {
		# initialize client and player stats for this period
		hourly_clients_max[ cur_period ] = cur_clients;
		hourly_clients_min[ cur_period ] = cur_clients - 1;
		hourly_players[ cur_period ] = cur_clients;
		delete player_check;
	}
	else if( cur_clients - 1 < hourly_clients_min[ cur_period ] ) {
		# update client stats for this period, if needed
		hourly_clients_min[ cur_period ] = cur_clients - 1;
	}
	if( player_check[ cur_user ] == NIL ) {
		# track another unique player
		player_check[ cur_user ] = 1;
	}

	for( p = get_period( _old_time ); p <= cur_period; p++ ) {
		# update session stats in all prior periods
		hourly_sessions[ p ]++;
	}

	# update some general stats
	if( lifetime > max_lifetime ) {
		max_lifetime = lifetime;
	}
	if( cur_time < rel_time + 86400 ) {
		if( max_clients == NIL || cur_clients > max_clients ) {
			max_clients = cur_clients;
		}
		if( min_clients == NIL || cur_clients - 1 < min_clients ) {
			min_clients = cur_clients - 1;
		}
	}
	if( !player_sessions[ cur_user ] ) {
		# if no previous sessions, it's a unique player
		total_players++;
	}
	total_sessions++;
	total_lifetime += lifetime;
	player_lifetime[ cur_user ] += lifetime;
	player_sessions[ cur_user ]++;
}

BEGIN {
	NIL = "";	# undefined variables are ambiguous (either 0 or "", so we'll create our own nil)

	TX_CREATE = 20;
	TX_SESSION_OPENED = 50;
	TX_SESSION_CLOSED = 51;
	TX_LOGIN_ATTEMPT = 30;
	TX_LOGIN_FAILURE = 31; 
	LOG_STARTED = 10;
	LOG_CHECKED = 11;
	LOG_STOPPED = 12;

	stat_bar[ 0 ] = "-";
	stat_bar[ 1 ] = "\\";
	stat_bar[ 2 ] = "|";
	stat_bar[ 3 ] = "/";
	stat_idx = 0;

	cur_period = 0;

	if( ARGC != 2 ) {
		throw( "The required arguments are missing, aborting." );
	}
	if( ARGV[ 1 ] != "-" && ARGV[ 1 ] !~ /\.dbx$/ ) {
		throw( "The specified journal file is not recognized, aborting." );
	}
	if( days !~ /^[0-9]+$/ ) {
		throw( "The required 'days' parameter is invalid, aborting." );
	}
	if( type != "txt" && type != "js" ) {
		throw( "The required 'type' parameter is invalid, aborting." );
	}

	# calculate the relative date from offset
	rel_date = ( int( systime( ) / 86400 ) - days )
	rel_time = rel_date * 86400;

	printf "Working on it..." > "/dev/tty";
}

{
	# show an animated progress indicator
	if( stat_idx++ % 50001 == 0 ) printf "%s\b", stat_bar[ stat_idx % 4 ] > "/dev/tty";

	cur_time = $1;
	if( $2 == TX_LOGIN_ATTEMPT ) {
		if( cur_time >= rel_time && cur_time < rel_time + 86400 ) {
			on_login_attempt( cur_time )
		}
        }
	else if( $2 == TX_LOGIN_FAILURE ) {
		if( cur_time >= rel_time && cur_time < rel_time + 86400 ) {
			on_login_failure( cur_time )
		}
        }
	else if( $2 == TX_CREATE ) {
		cur_user = $3;
		if( cur_time >= rel_time && cur_time < rel_time + 86400 ) {
			on_login_attempt( cur_time )
			on_create( cur_time, cur_user )
		}
        }
	else if( $2 == TX_SESSION_OPENED ) {
		# player joined game
		cur_user = $3;
		if( cur_time < rel_time + 86400 ) {
			player_login[ cur_user ] = cur_time;

			if( cur_time >= rel_time ) {
				# only track sessions within the specified timeframe
				on_session_opened( cur_time, cur_user )
			}
		}
		cur_clients++;
	}
	else if( $2 == TX_SESSION_CLOSED ) {
		# player left game
		cur_user = $3;
		if( cur_time >= rel_time && cur_user in player_login ) {
			# only track sessions within the specified timeframe
			on_session_closed( cur_time, cur_user )
		}
		cur_clients--;
		delete player_login[ cur_user ];
	}
	else if( $2 == LOG_STARTED ) {
		if( cur_time < rel_time + 86400 ) {
			on_server_startup( cur_time )
		}

		# sanity check (these should already not exist!)
		delete player_login;
		cur_clients = 0;
	}
	else if( $2 == LOG_STOPPED || $2 == LOG_CHECKED ) {
		if( cur_time >= rel_time && server_start != NIL ) {
			on_server_shutdown( cur_time )
		}

		# on server shutdown, all players logged off
		for( cur_user in player_login ) {
			if( cur_time >= rel_time ) {
				# only track sessions within the specified timeframe
				on_session_closed( cur_time, cur_user )
			}
		}
		# purge stale data for next server startup
		delete player_login;
		cur_clients = 0;
	}
}

END {
	# abort during an abnormal condition
	if( status ) exit;

	printf "Done!\n" > "/dev/tty";
	avg_lifetime = total_players > 0 ? total_lifetime / total_sessions : 0;

	if( type == "txt" ) {
		print "Daily Player Analytics Report (" strftime( "%d-%b-%Y UTC", rel_time, 1 ) ")\n";

		print "Player Activity: 24-Hour Totals";
		print "===========================================";
		print sprintf( " %-19s %10s %10s", "Player", "Sessions", "Lifetime", "Failures", "Attempts" );
		print "-------------------------------------------";
		for( i in player_sessions ) {
			print sprintf( " %-19s %10d %5dm %02ds", player_is_new[ i ] ? "* " i : i, player_sessions[ i ], player_lifetime[ i ] / 60, player_lifetime[ i ] % 60 );
		}
		print "-------------------------------------------";

		print "\nPlayer Activity: Hourly Totals";
		print "======================================================";
		print sprintf( " %-8s %10s %10s %10s %10s", "Period", "Sessions", "Failures", "Attempts", "Players" );
		print "------------------------------------------------------";
		for( i = 0; i < 24; i++ ) {
			print sprintf( " [%02d:00]  %10s %10s %10s %10s", i,
				i in hourly_sessions ? hourly_sessions[ i ] : 0,
				i in hourly_failures ? hourly_failures[ i ] : 0,
				i in hourly_attempts ? hourly_attempts[ i ] : 0,
				i in hourly_players ? hourly_players[ i ] : 0 );
		}
		print "------------------------------------------------------";

		print "\nPlayer Activity: Hourly Trends";
		print "===========================================";
		print sprintf( " %-9s %15s %15s", "Period", "Min Clients", "Max Clients" );
		print "-------------------------------------------";
		for( i = 0; i < 24; i++ ) {
			print sprintf( " [%02d:00]   %15s %15s", i,
				i in hourly_clients_min ? hourly_clients_min[ i ] : 0,
				i in hourly_clients_max ? hourly_clients_max[ i ] : 0 );
		}
		print "-------------------------------------------";

		print "\nPlayer Activity: 24-Hour Summary"
		print "===========================================";
		print sprintf( " %-30s %10d", "Total Players:", total_players );
		print sprintf( " %-30s %10d", "Total New Players:", total_players_new );
		print sprintf( " %-30s %10d", "Total Player Sessions:", total_sessions );
		print sprintf( " %-30s %10d", "Total Login Failures:", total_failures );
		print sprintf( " %-30s %10d", "Total Login Attempts:", total_attempts );
		print sprintf( " %-30s %9d%%", "Overall Server Uptime:", server_uptime / 86399 * 100 );
		print sprintf( " %-30s %10d", "Maximum Connected Clients:", max_clients );
		print sprintf( " %-30s %10d", "Minimum Connected Clients:", min_clients );
		print sprintf( " %-30s %5dm %02ds", "Maximum Player Lifetime:", max_lifetime / 60, max_lifetime % 60 );
		print sprintf( " %-30s %5dm %02ds", "Average Player Lifetime:", avg_lifetime / 60, avg_lifetime % 60 );
		print "-------------------------------------------";
	}
	else if( type == "js" ) {
		printf "{ datespec: %d, filespec: \"%s\", ", rel_date, ARGV[ 1 ];
		printf "global_stats: { total_players: %d, total_players_new: %d, total_sessions: %d, total_failures: %d, total_attempts: %d, server_uptime: %d, max_clients: %d, min_clients: %d, max_lifetime: %d, avg_lifetime: %d }, ",
			total_players, total_players_new, total_sessions, total_failures, total_attempts, server_uptime, max_clients, min_clients, max_lifetime, avg_lifetime;
		printf "hourly_stats: [ ";
		for( i = 0; i < 24; i++ ) {
			# printf coerces any nil values to zero automatically
			printf "{ sessions: %d, failures: %d, attempts: %d, players: %d, clients_max: %d, clients_min: %d }, ",
				hourly_sessions[ i ], hourly_failures[ i ], hourly_attempts[ i ], hourly_players[ i ], hourly_clients_max[ i ], hourly_clients_min[ i ];
		}
		printf "], ";
		printf "player_stats: { ";
		for( i in player_sessions ) {
			printf "\"%s\": { sessions: %d, lifetime: %d }, ", i, player_sessions[ i ], player_lifetime[ i ]
		}
		printf "} ";
		printf "};\n";
	}
}
