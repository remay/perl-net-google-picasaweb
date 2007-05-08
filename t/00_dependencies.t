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

# Test to see if we have Test::More available.  If not, then
# we can't perform the tests, and give up now.

eval "use Test::More";
if($@) {
	print "#\n";
    print "# Test::More is required for Net::Google::PicasaWeb testing.\n";
	chomp $@;
	$@ =~ s/^/# /gm;
	print "$@\n";
	print "Bail Out! Test::More not available\n";
}
else {
    plan(tests => 1);
    pass('Test::More is available');
}
