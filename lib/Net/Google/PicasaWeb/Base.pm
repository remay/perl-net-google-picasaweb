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
# Abstract Base class for User, Album, Photo, Comment
######################################################################

package Net::Google::PicasaWeb::Base;

our ($VERSION) = q$Revision$ =~ /(\d+)/xm;

our $AUTOLOAD;

use URI();
use Carp qw(croak carp);
use HTTP::Request();

use XML::Atom::Feed();

my %attributes = (
    parent     => undef,
    entry      => undef,
    feed       => undef,
    ua         => undef,
    last_error => undef,

    cli        => undef,
    username   => undef,
);

sub AUTOLOAD {
    my ($self, $value) = @_;
    my $method = $AUTOLOAD;
    $method =~ s/.*:://xm;

    # Some things to ignore
    return if $method eq 'DESTROY';

    # Type:
    my $type;
    if ($method =~ s/^_(get)_//xm or $method =~ s/^_(set)_//xm) {
        $type = $1;
    }

    # Allowed?
    if ($type and exists $attributes{$method}) {
        return  $self->{$method}           if $type eq 'get';
        return ($self->{$method} = $value) if $type eq 'set';
        # Don't get here
        die q(Internal Error);
    }

    my ($callpkg, $file, $line) = caller;
    croak qq(Attempt to AUTOLOAD unknown method '$AUTOLOAD'.\n) .
          qq(Called from $callpkg ($file, line $line)\n\t);
    return;
}

sub new { return bless { %attributes }, $_[0]; }

sub _get_relation {
    my ($self, $type) = @_;

    while (1) {
        return $self if $self->isa("Net::Google::PicasaWeb::$type");

        my $parent = $self->_get_parent;
        die q(Can't find a User) unless defined $parent;

        $self = $parent;
    }

    # Don't get here
    die q(Internal Error);
    return;
}

sub _get_user  { return $_[0]->_get_relation('User'); }
sub _set_user  { return $_[0]->_set_parent($_[1]); }
sub _get_album { return $_[0]->_get_relation("Album"); }
sub _set_album { return $_[0]->_set_parent($_[1]); }

sub _get_ua {
    my ($self) = @_;

    while (1) {
        my $ua = $self->{ua};
        return $ua if defined $ua;

        my $parent = $self->_get_parent;
        die q(Can't find a User Agent) unless defined $parent;

        $self = $parent;
    }

    # Don't get here
    die q(Internal Error);
    return;
}

sub is_authenticated { return $_[0]->_get_user->is_authenticated; }

sub _get_uri_from {
    my ($self, $from, $type, $typemap) = @_;

    # Check type:
    my $rel_type = $typemap->{$type};
    croak qq(Unrecognised type '$type') unless defined $rel_type;

    for my $link ($from->link) {
        return URI->new($link->href) if $link->rel eq $rel_type;
    }

    return;
}

sub _get_uri_from_feed {
    my ($self, $type) = @_;

    # turn type into rel:
    my %typemap = (
        feed => 'http://schemas.google.com/g/2005#feed',
        post => 'http://schemas.google.com/g/2005#post',
        html => 'alternate',
        self => 'self',
    );

    return $self->_get_uri_from($self->_get_feed, $type, \%typemap);
}

sub _get_uri_from_entry {
    my ($self, $type) = @_;

    # turn type into rel:
    my %typemap = (
        feed  => 'http://schemas.google.com/g/2005#feed',
        html  => 'alternate',
        self  => 'self',
        edit  => 'edit',
        medit => 'media-edit',
    );

    return $self->_get_uri_from($self->_get_entry, $type, \%typemap);
}

sub _get_feed {
    my ($self) = @_;

    # If we haven't got the feed, then get it
    unless (defined $self->{feed}) {

        # Find the User Agent:
        my $ua = $self->_get_ua;

        # Find the feed uri
        my $uri = $self->_get_uri_from_entry('feed');

        my $response = $ua->get($uri);

        if ( ! $response->is_success() ) {
            # Failed to get feed
             die qq(Failed to get feed from '$uri'.  Server said:\n) .
                 qq(---- Response Starts ----\n) .
                 $response->as_string() .
                 qq(----- Response Ends -----\n");
        }

        my $atom = $response->content();
        my $feed = XML::Atom::Feed->new(\$atom) or die 'Bad Feed';
        $self->_set_feed($feed);
    }

    # Return it
    return $self->{feed};
}

sub _invalidate_feed { $_[0]->_set_feed(); return 1; }

sub _add_entry_to_feed {
    my ($self, $entry) = @_;

    my $uri = $self->_get_uri_from_feed('post');
    my $ua  = $self->_get_ua;
    my $xml = $entry->as_xml;

    my $req = HTTP::Request->new(
        'POST',
        $uri,
        [
            Content_Length => length $xml,
            Content_Type   => 'application/atom+xml',
        ],
        $xml,
    );
        
    my $response = $ua->request($req);

    if ( ! $response->is_success() ) {
        $self->_set_last_error(
            qq(Failed to update feed at '$uri'.  Server said:\n) .
            qq(---- Response Starts ----\n) .
            $response->as_string() .
            qq(----- Response Ends -----\n")
        );
        return;
    }

    my $atom = $response->content();
    my $new_entry = XML::Atom::Entry->new(\$atom) or die 'Bad Entry';

    $self->_invalidate_feed();

    return $new_entry;
}

sub _update_entry {
  my ($self, $entry) = @_;

    my $uri = $self->_get_uri_from_entry('edit');
    my $ua  = $self->_get_ua;
    my $xml = $entry->as_xml;

    my $req = HTTP::Request->new(
        'PUT',
        $uri,
        [
            Content_Length => length $xml,
            Content_Type   => 'application/atom+xml',
        ],
        $xml,
    );
        
    my $response = $ua->request($req);

    if ( ! $response->is_success() ) {
        $self->_set_last_error(
            qq(Failed to update entry at '$uri'.  Server said:\n) .
            qq(---- Response Starts ----\n) .
            $response->as_string() .
            qq(----- Response Ends -----\n")
        );
        return;
    }

    my $atom = $response->content();
    my $new_entry = XML::Atom::Entry->new(\$atom) or die 'Bad Entry';

    $self->_set_entry($new_entry);

    my $parent = $self->_get_parent();
    $parent->_invalidate_feed if $parent;
    return $self;
}

sub _delete_entry {
  my ($self) = @_;

    my $uri = $self->_get_uri_from_entry('edit');
    my $ua  = $self->_get_ua;

    my $req = HTTP::Request->new(
        'DELETE',
        $uri,
    );
        
    my $response = $ua->request($req);

    if ( ! $response->is_success() ) {
        $self->_set_last_error(
            qq(Failed to update entry at '$uri'.  Server said:\n) .
            qq(---- Response Starts ----\n) .
            $response->as_string() .
            qq(----- Response Ends -----\n")
        );
        return;
    }

    my $parent = $self->_get_parent();
    $parent->_invalidate_feed if $parent;

    return 1;
}

1; # End of Base.pm
__END__

=pod

=cut
