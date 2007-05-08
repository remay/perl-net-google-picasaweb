#!perl
use strict;
use warnings;

BEGIN { $|++; } # AutoFlush

use Test::More tests => 1;

use_ok('Net::Google::PicasaWeb::Utils');
