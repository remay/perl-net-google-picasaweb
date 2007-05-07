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
__END__

=head1 NAME

Net::Google::PicasaWeb::Utils - Utility functions for working with picasweb

=head1 SYNOPSIS

  use Net::Google::PicasaWeb::Utils qw(
    format_bytes guess_block_size gphoto_timestamp_to_date
  );

=head1 DESCRIPTION

Net::Google::PicasaWeb::Utils is a (small) set of functions to assist
when working with Net::Google::PicasaWeb objects.

=head1 PUBLIC API

This section describes the public API.

By default this module exports nothing.  Any of the functions
described in this section can be exported by adding their name to the
import list on the 'use' line.

=head2 format_bytes

    my $string = format_bytes($bytes);

format_bytes() takes a number representing the size of something in
bytes, and formats the number as a human readable string.

    print format_bytes(1023);        # prints '1023 bytes'
    print format_bytes(1024);        # prints '1.000 KB'
    print format_bytes(1024*2000);   # prints '1.953 MB'

=head2 guess_block_size

  my $blocksize = guess_block_size($bytes, $speed);

guess_block_size() takes the number of bytes to be transfered and
the speed of a connection over which the bytes are to be transfered
(in bits per second), and suggests a transfer block size (in bytes)
to use, taking into account:

=over

=item *

No block should take more than one second to transfer.

=item *

The should be at least 100 blocks.

=back

These characteristics are designed to ensure that when transfering
large files (e.g. binary photo data) the reporting callbacks are
called regularly.  The suggested blocksize will never be less than
1024 bytes, regardless.

=head2 gphoto_timestamp_to_date

    my $date = gphoto_timestamp_to_date($timestamp);

gphoto_timestamp_to_date() takes a timestamp (as defined in the
Google Picasaweb Data API, gphoto namespace) and formats it
as a date.

The timestamp is the number of milli-seconds since January 1st,
1970.  See
L<http://code.google.com/apis/picasaweb/reference.html#gphoto_timestamp>
.

=head1 BUGS

gphoto_timestamp_to_date() currently formats the date it returns as a
European date.  I.e. December 2nd, 1980 appears as '2/12/1980'.  It
should be possible to set the format.

=head1 SEE ALSO

=over

=item L<http://code.google.com/apis/picasaweb/overview.html>

The Google Picasaweb Data API reference.

=item L<http://code.google.com/p/net-google-picasaweb/>

This module's homepage.

=back

=head1 AUTHOR

Robert May, E<lt>robertmay@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2007 by Robert May

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
