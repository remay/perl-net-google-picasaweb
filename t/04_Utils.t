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

use Net::Google::PicasaWeb::Utils
    qw(format_bytes guess_block_size gphoto_timestamp_to_date);

my $VERBOSE = 0;

my %formats = (
    '0'             => '0 bytes',
    '1'             => '1 bytes',
    '1023'          => '1023 bytes',
    '1024'          => '1.000 KB',
    '1048576'       => '1.000 MB',
    '1073741824'    => '1.000 GB',
    '1099511627776' => '1.000 TB',
);

my %speeds = (
    zero  =>         0,
    __9k6 =>     9_600,
    _14k4 =>    14_400,
    _56k0 =>    56_000,
    _128k =>   128_000,
    _512k =>   512_000,
    __1Mb => 1_000_000,
    __2Mb => 2_000_000,
);

my %sizes = (
    zero   =>         0,
    small  =>     3_000,
    medium => 1_000_000,
    large  => 5_000_000,
);

my %timestamps = (
    '1178481618000' => '06-05-2007',
);

my $tests = 0;
$tests += keys %formats;
$tests += 1;
$tests += ( 2 * (keys %speeds) * (keys %sizes) ); 
$tests += 4;
$tests += keys %timestamps;
$tests += 1;

plan tests => $tests;

######################################################################
# format_bytes()
######################################################################
{
    for my $bytes (keys %formats) {
        my $format = format_bytes($bytes);
        is ($format, $formats{$bytes}, "$bytes bytes becomes '$format'");
    }

    {
        # Check that no params is an error
        eval { format_bytes(); };
        my $error= $@;
        like($error, qr/Usage/, 'Usage printed for no params');
    }
}

######################################################################
# guess_block_size()
######################################################################
{

    # for each speed/size combination check that block size is never less than
    # 1024 byes, and that the time to transfer the block is not more than
    # one second.

    for my $speed (sort { $speeds{$a} <=> $speeds{$b} } keys %speeds) {
        for my $size (sort { $sizes{$a} <=> $sizes{$b} } keys %sizes) {

            diag qq(Speed: $speed\tFilesize: $size)if $VERBOSE;

            my $bs = guess_block_size( $sizes{$size}, $speeds{$speed} );
            cmp_ok($bs, '>=', 1024, "Block size: $bs");

            my $s = $speeds{$speed};
            my $time_per_block = $s == 0 ? 0 : $bs / ($s / 8);
            my $total_time     = $s == 0 ? 0 : $sizes{$size} / ($s / 8);
            cmp_ok($time_per_block, '<=', 1,
                sprintf('Time per block %.2fs (Total: %.2fs)', $time_per_block, $total_time));
        }
    }

    {
        # Check that no params is an error
        eval { guess_block_size(); };
        my $error= $@;
        like($error, qr/Usage/, 'Usage printed for no params');
    }

    {
        # Negative file size
        eval { guess_block_size( -1 ); };
        my $error= $@;
        like($error, qr/filesize.*negative/, 'Positive filesizes only');
    }

    {
        # Negative connect_speed
        eval { guess_block_size( 0, -1 ); };
        my $error= $@;
        like($error, qr/connect_speed.*negative/, 'Positive speeds only');
    }
    
    {
        # Undefined connect_speed
        my $bs = guess_block_size( 0 );
        is($bs, 1024 , 'Undefined connect speed allowed');
    }
}

######################################################################
# guess_block_size()
######################################################################
{
    for my $timestamp (keys %timestamps) {
        my $date = gphoto_timestamp_to_date($timestamp);
        is($date, $timestamps{$timestamp}, "$timestamp => $date");
    }
    
    {
        # Check that no params is an error
        eval { gphoto_timestamp_to_date(); };
        my $error= $@;
        like($error, qr/Usage/, 'Usage printed for no params');
    }
}
