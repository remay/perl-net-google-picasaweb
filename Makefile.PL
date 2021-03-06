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
# Makefile.PL for Net::Google::PicasaWeb
######################################################################

use 5.006;

use ExtUtils::MakeMaker;

my %config = (
    NAME          =>  'Net::Google::PicasaWeb',
    VERSION_FROM  =>  'lib/Net/Google/PicasaWeb.pm',

    ($] >= 5.005 ? (
        ABSTRACT_FROM =>  'lib/Net/Google/PicasaWeb.pm',
        AUTHOR        =>  'Robert May <robertmay@cpan.org>',
    ) : () ),

    LICENSE       =>  'perl',

    PREREQ_PM     => {
            'LWP'           => 0,
            'Crypt::SSLeay' => 0,
            'Scalar::Util'  => 0,
            'XML::Atom'     => 0,
            'Test::More'    => 0,
                     },
);

WriteMakefile(%config);
