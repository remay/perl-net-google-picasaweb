#!perl -wT
use strict;
use warnings;

use Test::More tests => 1;

$|++; # AutoFlush

use_ok('Net::Google::PicasaWeb::ClientLogin');
