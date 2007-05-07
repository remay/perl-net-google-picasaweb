#!perl -w
use strict;
use warnings;

# Makefile.PL for Net::Google::PicasaWeb

use ExtUtils::MakeMaker;

my %config = (
    NAME          =>  'Net::Google::PicasaWeb',
    AUTHOR        =>  'Robert May <robertmay@cpan.org>',
    VERSION_FROM  =>  'lib/Net/Google/PicasaWeb.pm',
    ABSTRACT_FROM =>  'lib/Net/Google/PicasaWeb.pm',
);

WriteMakefile(%config);
