#!perl -w
use strict;
use warnings;

######################################################################
# net-google-picasaweb project. Implementing the API detailed at:
# http://code.google.com/apis/picasaweb/reference.html
#
# Copyright (C) 2007 by Robert May
#
# This library is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
######################################################################
# $Id$
######################################################################

######################################################################
# On some operating systems (Windows notably) you can't use
# Devel::Cover with fork(), as needed by many of the tests to provide
# mock server.  This script starts the server as a stand alone script,
# and prints the server's URL to the console.
#
# If you then set the environment variable TEST_SERVER_URL
# in the environment of the tests being run:
# TEST_SERVER_URL=http://host:port/ make test
# (or something similar)
# then the tests will use this server, rather than trying to spawn
# their own.

use FindBin;
use lib $FindBin::Bin;
require 'TestServer.pmt';

print qq(Starting Server ...\n);
my $server = TestServer->new;
print qq(Configuring Server ...\n);
$server->configure('ClientLogin');
my $server_url = $server->spawn();
print qq(Server listenting at $server_url ...\n);

$server->wait;
