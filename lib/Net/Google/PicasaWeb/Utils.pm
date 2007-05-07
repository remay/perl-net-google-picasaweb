#!perl -wT
use strict;
use warnings;

package Net::Google::PicasaWeb::Utils;

our $VERSION = "0.00_01";
eval $VERSION;

use Carp qw(croak);
use Exporter qw(import);

our @EXPORT_OK = qw(format_bytes guess_block_size gphoto_timestamp_to_date);

# Stolen from ActiveState::Bytes and modified
sub format_bytes {
    my ($n) = @_;

    croak q(Usage: format_bytes($bytes)) if @_ < 1;

    return sprintf "%.3f TB", $n / (1024 * 1024 * 1024 * 1024)
	if $n >= 1024 * 1024 * 1024 * 1024;

    return sprintf "%.3f GB", $n / (1024 * 1024 * 1024)
	if $n >= 1024 * 1024 * 1024;

    return sprintf "%.3f MB", $n / (1024 * 1024)
	if $n >= 1024 * 1024;
    
    return sprintf "%.3f KB", $n / 1024
	if $n >= 1024;

    return "$n bytes";
}

# Want to calculate the blocksize such that(in priority order)
# (1) min blocksize is 1024 bytes
# (2) we get no more than 100 blocks
# (3) a block doesn't take more than one second
# filesize in bytes, speed in bits/s
sub guess_block_size {
	my ($filesize, $speed) = @_;
	# Filesize in bytes, speed in kbits/s

    croak('Usage: guess_block_size($filesize, $connect_speed)') if @_ < 1;
    croak('filesize cannot be negative') if $filesize < 0;
    # Use default slowish speed, if speed not passed
    $speed = 40000 if (!defined $speed) or ($speed == 0);
    croak('connect_speed cannot be negative') unless $speed > 0;

	# Initial minimum size
	my $block_size = 1024;

	# Increase block size, if we can do, allowing
	# a maximum of 100 bloack
	$block_size = $filesize / 100 if $filesize / 100 > $block_size;

	# Reduce block size to ensure a block does not
	# take more than 1 second
	$block_size = $speed / 8 if $speed / 8 < $block_size;

	# Reduce block size to next lower power of 2.
	my $r = int ( log($block_size) / log(2) );
	$block_size = 2 ** $r;

	return $block_size;
}

sub gphoto_timestamp_to_date {
    my ($timestamp) = @_;

    croak q(Usage: gphoto_timestamp_to_date($timestamp)) if @_ < 1;

    my ($mday, $mon, $year) = (gmtime(int($timestamp/1000)))[3,4,5];
    $year += 1900;
    $mon += 1;

    return sprintf("%02d-%02d-%4d", $mday, $mon, $year);
}

1; # End of Utils.pm
