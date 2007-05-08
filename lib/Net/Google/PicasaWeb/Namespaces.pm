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
	gphoto     => XML::Atom::Namespace->new('gphoto'    ,'http://schemas.google.com/photos/2007'      ),
	media      => XML::Atom::Namespace->new('media'     ,'http://search.yahoo.com/mrss/'              ),
	exif       => XML::Atom::Namespace->new('exif'      ,'http://schemas.google.com/photos/exif/2007' ),
    #openSearch => XML::Atom::Namespace->new('openSearch','http://a9.com/-/spec/opensearchrss/1.0/'    ),
    #geo        => XML::Atom::Namespace->new('geo'       ,'http://www.w3.org/2003/01/geo/wgs84_pos#'   ),
    #photo      => XML::Atom::Namespace->new('photo'     ,'http://www.pheed.com/pheed/'                ),
    #georss     => XML::Atom::Namespace->new('georss'    ,'http://www.georss.org/georss'               ),
    #batch      => XML::Atom::Namespace->new('batch'     ,'http://schemas.google.com/gdata/batch'      ),
    #gml        => XML::Atom::Namespace->new('gml'       ,'http://www.opengis.net/gml'                 ),
);

my %namespace_lookup = map { $namespaces{$_}->{uri} => $namespaces{$_} } keys %namespaces;

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
		$obj->elem->setNamespace($namespaces{$_}->{uri}, $namespaces{$_}->{prefix}, 0);
	}

	$obj;
}
	
package XML::Atom::Gphoto;

our @ISA = qw( Net::Google::PicasaWeb::Namespaces );

use XML::Atom::Util qw(childlist);

__PACKAGE__->mk_elem_accessors(qw( albumid commentCount commentingEnabled id maxPhotosPerAlbum
                                   nickname quotacurrent quotalimit thumbnail user access
							       bytesUsed location name numphotos numphotosremaining
							       checksum client height position rotation size timestamp
							       version width photoid weight ));

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

__PACKAGE__->mk_elem_accessors(qw( credit description keywords title ));

__PACKAGE__->mk_object_list_accessor('content' => 'XML::Atom::MediaGroup::Content', 'contents');
__PACKAGE__->mk_object_list_accessor('thumbnail' => 'XML::Atom::MediaGroup::Thumbnail', 'thumbnails');

for my $class (qw( XML::Atom::Feed XML::Atom::Entry )) {
    __PACKAGE__->mk_object_accessor( $class, group => __PACKAGE__ );
}

sub element_name { 'group' }
sub element_ns   { $namespaces{media}->{uri} }

package XML::Atom::MediaGroup::Content;

our @ISA = qw( Net::Google::PicasaWeb::Namespaces );

__PACKAGE__->mk_attr_accessors(qw( url type medium height width filesize ));

sub element_name { 'content' }
sub element_ns   { $namespaces{media}->{uri} }

package XML::Atom::MediaGroup::Thumbnail;

our @ISA = qw( Net::Google::PicasaWeb::Namespaces );

__PACKAGE__->mk_attr_accessors(qw( url height width ));

sub element_name { 'thumbnail' }
sub element_ns   { $namespaces{media}->{uri} }

package XML::Atom::Exiftags;

our @ISA = qw( Net::Google::PicasaWeb::Namespaces );

__PACKAGE__->mk_elem_accessors(qw( fstop make model distance exposure flash focallength iso time ));

for my $class (qw( XML::Atom::Feed XML::Atom::Entry )) {
    __PACKAGE__->mk_object_accessor( $class, tags => __PACKAGE__ );
}

sub element_name { 'tags' }
sub element_ns   { $namespaces{exif}->{uri} }

1; # End of Namespaces.pm

__END__
