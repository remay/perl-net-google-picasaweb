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

package Net::Google::PicasaWeb::Namespaces;

our ($VERSION) = q$Revision$ =~ /(\d+)/;
eval $VERSION;

our @ISA = qw( XML::Atom::Base );

use XML::Atom();
use XML::Atom::Feed();
use XML::Atom::Entry();
use XML::Atom::Util qw( childlist );

$XML::Atom::DefaultVersion = '1.0';

my %namespaces = (
	gphoto     => XML::Atom::Namespace->new('gphoto',
                    'http://schemas.google.com/photos/2007'),
	media      => XML::Atom::Namespace->new('media',
                    'http://search.yahoo.com/mrss/'),
	exif       => XML::Atom::Namespace->new('exif',
                    'http://schemas.google.com/photos/exif/2007' ),
);

my %namespace_lookup = map
                       { $namespaces{$_}->{uri} => $namespaces{$_} }
                       keys %namespaces;

sub mk_object_accessor {
    my $class = shift;
    my($mkclass, $name, $ext_class) = @_;
    no strict 'refs';
    (my $meth = $name) =~ tr/\-/_/;
    *{"${mkclass}::$meth"} = sub {
        my $obj = shift;
        my $ns_uri = $ext_class->element_ns || $obj->ns;
        if (@_) {
            my $ns = $namespace_lookup{$ns_uri} || $ns_uri;
            return $obj->set($ns, $name, $_[0]);
        } else {
            return $obj->get_object($ns_uri, $name, $ext_class);
        }
    };
}

sub mk_elem_accessors {
    my $class = shift;
    my(@list) = @_;
    no strict 'refs';
    for my $elem (@list) {
        (my $meth = $elem) =~ tr/\-/_/;
        *{"${class}::$meth"} = sub {
            my $obj = shift;
			my $ns_uri = $obj->ns;
            if (@_) {
                my $ns = $namespace_lookup{$ns_uri} || $ns_uri;
                return $obj->set($ns, $elem, $_[0]);
            } else {
                return $obj->get($ns_uri, $elem);
            }
        };
    }
}

sub mk_object_list_accessor {
    my $class = shift;
    my($name, $ext_class, $moniker) = @_;

    no strict 'refs';

    *{"$class\::$name"} = sub {
        my $obj = shift;

        my $ns_uri = $ext_class->element_ns || $obj->ns;
        if (@_) {
            # setter: clear existent elements first
            my @elem = childlist($obj->elem, $ns_uri, $name);
            for my $el (@elem) {
                $obj->elem->removeChild($el);
            }

            # add the new elements for each
            my $adder = "add_$name";
            for my $add_elem (@_) {
                $obj->$adder($add_elem);
            }
        } else {
            # getter: just call get_object which is a context aware
            return $obj->get_object($ns_uri, $name, $ext_class);
        }
    };

    # moniker returns always list: array ref in a scalar context
    if ($moniker) {
        *{"$class\::$moniker"} = sub {
            my $obj = shift;
            if (@_) {
                return $obj->$name(@_);
            } else {
                my @obj = $obj->$name;
                return wantarray ? @obj : \@obj;
            }
        };
    }

    # add_$name
    *{"$class\::add_$name"} = sub {
        my $obj = shift;
        my($stuff) = @_;

        my $ns_uri = $ext_class->element_ns || $obj->ns;
		my $ns = $namespace_lookup{$ns_uri} || $ns_uri;
        my $elem = ref $stuff eq $ext_class ?
            $stuff->elem : create_element($ns, $name);
        $obj->elem->appendChild($elem);

        if (ref($stuff) eq 'HASH') {
            for my $k ( $ext_class->attributes ) {
                defined $stuff->{$k} or next;
                $elem->setAttribute($k, $stuff->{$k});   # TODO: should this be setAttributeNS?
            }
        }
    };
}

######################################################################
# Specialised XML::Atom::Entry constructor to get NS right
######################################################################
package XML::Atom::PicasaEntry;

our @ISA = qw( XML::Atom::Entry );

sub init {
	my $obj = shift;
	$obj->SUPER::init(@_);

	for (keys %namespaces) {
		$obj->elem->setNamespace(
            $namespaces{$_}->{uri},
            $namespaces{$_}->{prefix},
            0
        );
	}

	$obj;
}
	
package XML::Atom::Gphoto;

our @ISA = qw( Net::Google::PicasaWeb::Namespaces );

use XML::Atom::Util qw(childlist);

__PACKAGE__->mk_elem_accessors(qw(
    albumid commentCount commentingEnabled id maxPhotosPerAlbum
    nickname quotacurrent quotalimit thumbnail user access bytesUsed
    location name numphotos numphotosremaining checksum client height
    position rotation size timestamp version width photoid weight
));

for my $class (qw( XML::Atom::Feed XML::Atom::Entry )) {
    __PACKAGE__->mk_object_accessor( $class, gphoto => __PACKAGE__ );
}

sub element_name { 'gphoto' }
sub element_ns   { $namespaces{gphoto}->{uri} }

sub mk_object_accessor {
    my $class = shift;
    my($mkclass, $name, $ext_class) = @_;
    no strict 'refs';
    (my $meth = $name) =~ tr/\-/_/;
    *{"${mkclass}::$meth"} = sub {
        my $obj = shift;
        my $ns_uri = $ext_class->element_ns || $obj->ns;
		my $ns = $namespace_lookup{$ns_uri} || $ns_uri;
        if (@_) {
			# Setter: (1) remove all gphoto namespace items
			# (2) add the new ones
			my @elem = childlist($obj->elem, $ns_uri, '*');
            for my $el (@elem) {
                $obj->elem->removeChild($el);
            }

			@elem = childlist($_[0]->elem, $ns_uri, '*');
			for my $el (@elem) {
				$obj->elem->appendChild($el);
			}

            return $obj;
        } else {
			my @elem = childlist($obj->elem, $ns_uri, '*');
			my $new_obj = $ext_class->new();
			for my $el (@elem) {
				my $name = $el->localname;
				my $value = $el->textContent;
				$new_obj->$name($value);
			}
            return $new_obj;
        }
    };
}

package XML::Atom::MediaGroup;

our @ISA = qw( Net::Google::PicasaWeb::Namespaces );

__PACKAGE__->mk_elem_accessors(qw(
    credit description keywords title
));

__PACKAGE__->mk_object_list_accessor(
    'content' => 'XML::Atom::MediaGroup::Content', 'contents'
);
__PACKAGE__->mk_object_list_accessor(
    'thumbnail' => 'XML::Atom::MediaGroup::Thumbnail', 'thumbnails'
);

for my $class (qw( XML::Atom::Feed XML::Atom::Entry )) {
    __PACKAGE__->mk_object_accessor( $class, group => __PACKAGE__ );
}

sub element_name { 'group' }
sub element_ns   { $namespaces{media}->{uri} }

package XML::Atom::MediaGroup::Content;

our @ISA = qw( Net::Google::PicasaWeb::Namespaces );

__PACKAGE__->mk_attr_accessors(qw(
    url type medium height width filesize
));

sub element_name { 'content' }
sub element_ns   { $namespaces{media}->{uri} }

package XML::Atom::MediaGroup::Thumbnail;

our @ISA = qw( Net::Google::PicasaWeb::Namespaces );

__PACKAGE__->mk_attr_accessors(qw( url height width ));

sub element_name { 'thumbnail' }
sub element_ns   { $namespaces{media}->{uri} }

package XML::Atom::Exiftags;

our @ISA = qw( Net::Google::PicasaWeb::Namespaces );

__PACKAGE__->mk_elem_accessors(qw(
    fstop make model distance exposure flash focallength iso time
));

for my $class (qw( XML::Atom::Feed XML::Atom::Entry )) {
    __PACKAGE__->mk_object_accessor( $class, tags => __PACKAGE__ );
}

sub element_name { 'tags' }
sub element_ns   { $namespaces{exif}->{uri} }

1; # End of Namespaces.pm

__END__

=head1 NAME

Net::Google::PicasaWeb::Namespaces - Namespace extensions to XML::Atom

=head1 SYNOPSIS

  use Net::Google::PicasaWeb::Namespaces;

  my $entry = XML::Atom::Picas::Entry->new();

=head1 DESCRIPTION

Net::Google::PicasaWeb::Namespaces provides extensions to the
XML::Atom package for creating and parsing the additional
namespace elements that the Google Picasa Web Data API
provides.

This module is used internally by Net::Google::PicasaWeb, and it
is not expected that an end-user of the module will ever need to
use this module directly.  This documentation is for developers.

=head1 EXPORTS

This module exports nothing.

=head1 Classes

This module provides the following classes:

=head2 Net::Google::PicasWeb::Namespaces

Sub-class of XML::Atom::Base, and base class for other classes
provided here.

Provides namespace definitions for the gphoto, media and exif
namespaces, and overrides the following XML::Atom::Base methods
to add the namespace support in a way that results in neat
XML generation:

=over

=item mk_object_accessor

Modified from the XML::Atom::Base implementation to provide
an XML::Atom::Namespace object to the set() method, rather than
a simple URI.  This allows XML::XMLLib to generate XML with the
namespace definition (xmlns attribute) on the root element of the
generated XML.

=item mk_elem_accessors

Modified from the XML::Atom::Base implementation to provide
an XML::Atom::Namespace object to the set() method, rather than
a simple URI.  This allows XML::XMLLib to generate XML with the
namespace definition (xmlns attribute) on the root element of the
generated XML.

=item mk_object_list_accessor

Modified from the XML::Atom::Base implementation to provide
class over-ridable namespaces.  Further modified to create the
accessor in a named package, as the original implementation required
calling this as a method of the class into which the accesors should
be created, and it's not possible to sub-class that without subclassing
virtually everything in XML::Atom.  And I didn't want to do that ...

=back

=head2 XML::Atom::PicasaEntry

Subclass of XML::Atom::Entry, which adds the namespace definitions to
the root element of the Entry being generated.  Allows for neater XML
generation.  Otherwise an object of this class behaves exactly like
an XML::Atom::Entry object.

=head2 XML::Atom::Gphoto

  my $timestamp = $entry->gphoto->timestamp; # getter

  my $gphoto = XML::Atom::Gphoto->new();
  $gphoto->timestamp($timestamp);
  $entry->gphoto($gphoto);

Subclass of Net::Google::PicasaWeb::Namespace to provide accessors
for the gphoto namespace.  To avoid accessor name clashes the gphoto
elements are treated as is they were encapsulated within a
C<< <gphoto> >> element, even thought they actually appear as direct
children of the root element in the XML.  Hence the syntax above.

The following gphoto elements are covered, having accessors with the
same names:

albumid, commentCount, commentingEnabled, id, maxPhotosPerAlbum,
nickname, quotacurrent, quotalimit, thumbnail, user, access,
bytesUsed, location, name, numphotos, numphotosremaining, checksum,
client, height, position, rotation, size, timestamp, version, width,
photoid, weight.

Overrides the following methods to enable this behaviour:

=over

=item mk_object_accessor

Modified from the base class implementation to treat the elements
as if they are part of a sub-group, when they are not.

=item element_name

Returns 'gphoto'.

=item element_ns

Returns the gphoto namespace URI.

=back

=head2 XML::Atom::MediaGroup

  my $credit = $entry->group->credit; # getter

  my $media_group = XML::Atom::MediaGroup->new();
  $media_group->credit($credit);
  $entry->group($media_group);

Subclass of Net::Google::PicasaWeb::Namespace to provide accessors
for the media namespace.  These elements appears within their own
C<< <group> >> element.

Provides simple accessors for the following elements: credit,
description, keywords, title.

See below for the contents and thumbnail accessors.

Overrides the following methods:

=over

=item element_name

Returns 'group'.

=item element_ns

Returns the media namespace URI.

=back

=head2 XML::Atom::MediaGroup::Content

  my @contents = $entry->group->content();
  my $content_url = $contents[0]->url;

  my $content = XML::Atom::MediaGroup::Content->new();
  $content->url($content_url);
  $content->type('image/jpeg');
  ...
  $media_group->add_content($content);
  ...

Subclass of Net::Google::PicasaWeb::Namespace to provide accessors
for the attributes of a media::content element.  The accessors and
setters work just link those of an XML::Atom::Link object, as there
can me more than one content element per media group.

Provides simple accessors for the following attributes: url,
type, medium, height, width, filesize.

Overrides the following methods:

=over

=item element_name

Returns 'content'.

=item element_ns

Returns the media namespace URI.

=back

=head2 XML::Atom::MediaGroup::Thumbnail

  my @thumbs = $entry->group->thumbnail();
  my $thumb_height = $thumbs[0]->height;

  my $thumb = XML::Atom::MediaGroup::Thumbnail->new();
  $thumb->url($thumb_url);
  $thumb->height(150);
  ...
  $media_group->add_thumb($thumb);
  ...

Subclass of Net::Google::PicasaWeb::Namespace to provide accessors
for the attributes of a media thumbnail element.  The accessors and
setters work just link those of an XML::Atom::Link object, as there
can me more than one thumbnail element per media group.

Provides simple accessors for the following attributes: url,
height, width.

Overrides the following methods:

=over

=item element_name

Returns 'thumbnail'.

=item element_ns

Returns the media namespace URI.

=back

=head2 XML::Atom::Exiftags

  my $exposure = $entry->tags->exposure; # getter

  my $exif_tags = XML::Atom::Exiftags->new();
  $exif_tags->exposure($exposure);
  ...
  $entry->tags($exif_tags);

Subclass of Net::Google::PicasaWeb::Namespace to provide accessors
for the exif namespace.  These elements appears within their own
C<< <exif:tags> >> element.

Provides simple accessors for the following elements: fstop,
make, model, distance, exposure, flash, focallength, iso, time.

Overrides the following methods:

=over

=item element_name

Returns 'tags'.

=item element_ns

Returns the exif namespace URI.

=back

=head1 BUGS

It's a bit messy, but at least it encapsulate the mess here, rather
than all over the source.

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
