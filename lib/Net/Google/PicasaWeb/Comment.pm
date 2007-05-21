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

package Net::Google::PicasaWeb::Comment;

our ($VERSION) = q$Revision$ =~ /(\d+)/xm;

use Net::Google::PicasaWeb::Base qw();
use Net::Google::PicasaWeb::Namespaces qw();

our @ISA = qw(Net::Google::PicasaWeb::Base);

use Carp qw(croak carp);
use Scalar::Util qw(blessed);

sub new {
    my ( $class, $entry, $photo ) = @_;

    # Must have an entry and an album object
    croak 'Usage: ' . __PACKAGE__ . '->new($entry, $photo)' if @_ < 3;
    croak qq(Parameter 1 to $class->new must be a comment entry object)
        if not( bessed($entry) and $entry->isa('XML::Atom::Entry') );
    croak qq(Parameter 2 to $class->new must be a photo object)
        if not( blessed($photo)
        and $photo->isa('Net::Google::PicasaWeb::Photo') );

    my $self = $class->SUPER::new();

    $self->_set_photo($photo);
    $self->_set_entry($entry);

    return $self;
}

sub title   { return $_[0]->_get_entry->title; }
sub summary { return $_[0]->_get_entry->summary; }
sub id      { return $_[0]->_get_entry->gphoto->id; }

sub describe {
    my ($self) = @_;

    print $self->title, "\t[", $self->summary, "] \n";

    return;
}

sub update {
    my ( $self, $opts ) = @_;

    # XXX
    croak q(Not yet implemented);

    croak 'Usage: $photo->update_info(\%opts)' if @_ < 1;

    # Opts must be a hash ref
    $opts ||= {};
    croak q(opts must be a hash ref.) if ref($opts) ne 'HASH';

    # Pre-requsites
    croak qq(Must be logged in to update.) if not $self->is_authenticated();

    # Allowed options and default values:
    my %options = (
        title   => $self->title,
        summary => $self->summary,
    );

    # Check supplied options
    for ( keys %{$opts} ) {
        if ( not exists $options{$_} ) {
            carp qq(Ignoring unrecognised option '$_');
            delete $opts->{$_};
        }
    }

    # Apply supplied options
    %options = ( %options, %{$opts} );

    # Create <entry> for comment
    my $entry = XML::Atom::PicasaEntry->new();
    $entry->title( $options{title} );
    $entry->summary( $options{summary} );
    my $category = XML::Atom::Category->new();
    $category->scheme('http://schemas.google.com/g/2005#kind');
    $category->term('http://schemas.google.com/photos/2007#comment');
    $entry->category($category);

    return $self->_update_entry($entry);
}

sub delete {
    croak q(Not yet implemented);
}

1;    # End of Comment.pm
__END__

=pod

=cut
