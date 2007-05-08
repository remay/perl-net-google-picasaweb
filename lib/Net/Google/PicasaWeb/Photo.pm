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

package Net::Google::PicasaWeb::Photo;

our ($VERSION) = q$Revision$ =~ /(\d+)/;
eval $VERSION;

use Net::Google::PicasaWeb::Base();
use Net::Google::PicasaWeb::Namespaces();
use Net::Google::PicasaWeb::Utils qw(format_bytes);

our @ISA = qw(Net::Google::PicasaWeb::Base);

use Carp qw(croak carp);
use URI();

sub new {
    my ($class, $entry, $album) = @_;

    # Must have an entry and an album object
    croak 'Usage: ' . __PACKAGE__ . '->new($entry, $album)' if @_ < 3;
    croak qq(Parameter 1 to $class->new must be a photo entry object)
        unless ref($entry) and $entry->isa('XML::Atom::Entry');
    croak qq(Parameter 2 to $class->new must be an album object)
        unless ref($album) and $album->isa('Net::Google::PicasaWeb::Album');

    my $self = $class->SUPER::new();

    $self->_set_album($album);
    $self->_set_entry($entry);

    return $self;
}

sub title    { $_[0]->_get_entry->title; }
sub summary  { $_[0]->_get_entry->summary; }
sub id       { $_[0]->_get_entry->gphoto->id; }
sub width    { $_[0]->_get_entry->gphoto->width; }
sub height   { $_[0]->_get_entry->gphoto->height; }
sub size     { $_[0]->_get_entry->gphoto->size; }
sub keywords { $_[0]->_get_entry->group->keywords; }

sub describe {
    my ($self) = @_;

    print $self->title, "\t[", $self->summary, "] ", $self->width, "x",
    $self->height, " ", format_bytes($self->size), "\n";

    return 1;
}

sub update_info {
    my ($self, $opts) = @_;

    croak 'Usage: $photo->update_info(\%opts)' if @_ < 1;

    # Opts must be a hash ref
    $opts = {} unless defined $opts;
    croak q(opts must be a hash ref.) unless ref($opts) eq 'HASH';

    # Pre-requsites
    croak qq(Must be logged in to update.) unless $self->is_authenticated();

    # Allowed options and default values:
    my %options = ( 
        title    => $self->title, 
        summary  => $self->summary, 
        keywords => $self->keywords, 
    );

    # Check supplied options
    for (keys %$opts) {
        unless (exists $options{$_}) {
            carp qq(Ignoring unrecognised option '$_');
            delete $opts->{$_};
        }
    }

    # Apply supplied options
    %options = ( %options, %$opts );

    # Create <entry> for photo
    my $entry = XML::Atom::PicasaEntry->new();
    $entry->title($options{title});
    $entry->summary($options{summary});
        my $media_group = XML::Atom::MediaGroup->new();
        $media_group->keywords($options{keywords});
    $entry->group($media_group);
        my $category = XML::Atom::Category->new();
        $category->scheme('http://schemas.google.com/g/2005#kind');
        $category->term('http://schemas.google.com/photos/2007#photo');
    $entry->category($category);

    return $self->_update_entry($entry);
}

sub update_picture {
    croak q(Not yet implemented);
}

sub delete {
    croak q(Not yet implemented);
}

1; # End of PicasaWeb.pm
