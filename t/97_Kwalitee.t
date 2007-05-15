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

BEGIN { $|++; } # AutoFlush

use Test::More;

if ( not $ENV{TEST_AUTHOR} ) {
    my $msg = 'Author test.  Set $ENV{TEST_AUTHOR} to a true value to run.';
    plan( skip_all => $msg );
}

# OK, so Test::Kwalitee 0.30 doen't play nicely with Module::CPANTS::Analyse
# 0.71.  I've sort of fixed my version, but has_example, proper_libs,
# has_test_pod, and has_test_pod_coverage all fail under Win32 due to wrong
# path seperator checks (/' not '\').  Also, as we don't have a ny modules
# using us yet is_prereq fails, so exclude it.
eval { require Test::Kwalitee; Test::Kwalitee->import( tests => [
    qw( -has_example -proper_libs -has_test_pod
        -has_test_pod_coverage -is_prereq ) ] );
};
plan( skip_all => 'Test::Kwalitee not installed; skipping' ) if $@;
