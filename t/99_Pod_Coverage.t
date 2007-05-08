#!perl -wT
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

BEGIN { $|++; } # AutoFlush

use Test::More;

eval "use Test::Pod::Coverage 1.04";
plan skip_all => "Test::Pod::Coverage 1.04 required for testing POD coverage"
        if $@;

all_pod_coverage_ok();
