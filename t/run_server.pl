#!perl -w
use strict;
use warnings;

######################################################################
# Start the server

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
