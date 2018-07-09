#####################################################################
#
# disallow new players whenever server is overloaded
#
#####################################################################

try "There are too many players online right now."

fail all
if $is_new eq $true
if $cur_users gt 20
continue

#####################################################################
#
# only allow administrator access (by username or IP address)
#
#####################################################################

pass any
if $addr eq "172.16.100.1"
if $addr eq "172.16.100.2"
if $name eq "admin"
continue

#####################################################################
#
# block a range of IP addresses using wildcards
#
#####################################################################

try "This subnet is blocked by the administrator."

fail any
if $addr is /192.88.99.*/
if $addr is /203.0.113.*/
if $addr is /192.168.*.*/
continue

pass now

#####################################################################
#
# only allow access from whitelisted users
#
#####################################################################

try "The account '$name' is not permitted to join this server."

pass any
if $name eq "admin"
when @whitelist.txt eq $name
continue

fall now

#####################################################################
#
# never allow access from blacklisted users
#
#####################################################################

try "The account '$name' is not permitted to join this server."
fail all
when @blacklist.txt eq $name
continue

pass now

#####################################################################
#
# notify users that the server is unavailable right now
#
#####################################################################

try "The server is temporarily offline for maintenance."

fail now
