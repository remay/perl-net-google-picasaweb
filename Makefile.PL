#!perl -w
use strict;
use warnings;

# Makefile.PL for Net::Google::PicasaWeb

use 5.006;

use ExtUtils::MakeMaker;

my %config = (
    NAME          =>  'Net::Google::PicasaWeb',
    VERSION_FROM  =>  'lib/Net/Google/PicasaWeb.pm',

    ($] >= 5.005 ? (
        ABSTRACT_FROM =>  'lib/Net/Google/PicasaWeb.pm',
        AUTHOR        =>  'Robert May <robertmay@cpan.org>',
    ) : () ),
);

WriteMakefile(%config);
