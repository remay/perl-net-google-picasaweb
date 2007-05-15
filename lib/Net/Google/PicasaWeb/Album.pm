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

package Net::Google::PicasaWeb::Album;

our ($VERSION) = q$Revision$ =~ /(\d+)/xm;

use Net::Google::PicasaWeb::Base();
use Net::Google::PicasaWeb::Photo();
use Net::Google::PicasaWeb::Namespaces();
use Net::Google::PicasaWeb::Utils qw(guess_block_size gphoto_timestamp_to_date);

our @ISA = qw(Net::Google::PicasaWeb::Base);

use Carp qw(croak carp);
use File::Basename qw(fileparse);
use HTTP::Request();
use LWP::MediaTypes qw(guess_media_type);
use URI();

sub new {
    my ($class, $entry, $user) = @_;

    # Must have an entry and a user object
    croak 'Usage: ' . __PACKAGE__ . '->new($entry, $user)' if @_ < 3;
    croak qq(Parameter 1 to $class->new must be an album entry object)
        unless ref $entry and $entry->isa('XML::Atom::Entry');
    croak qq(Parameter 2 to $class->new must be a user object)
        unless ref $user and $user->isa('Net::Google::PicasaWeb::User');

    my $self = $class->SUPER::new();

    $self->_set_user($user);
    $self->_set_entry($entry);

    return $self;
}

sub title     { return $_[0]->_get_entry->title; }
sub summary   { return $_[0]->_get_entry->summary; }
sub rights    { return $_[0]->_get_entry->rights; }
sub id        { return $_[0]->_get_entry->gphoto->id; }
sub numphotos { return $_[0]->_get_entry->gphoto->numphotos; }
sub location  { return $_[0]->_get_entry->gphoto->location; }
sub timestamp { return $_[0]->_get_entry->gphoto->timestamp; }

sub date { return gphoto_timestamp_to_date($_[0]->timestamp()); }

sub describe {
    my ($self) = @_;

    print $self->title, "\t[", $self->summary, "]\n";
    print '  Album ID: ', $self->id, ' - ', $self->numphotos, ' ', $self->rights, " photo(s)\n";
    print '  Location: ', $self->location, " \n";

    return 1;
}

sub update {
    croak q(Not yet implemented);
}

sub delete {
    my ($self) = @_;

    my $r = $self->_delete_entry();
    $_[0] = undef if $r;

    return $r;
}

sub get_photos {
    my ($self) = @_;

    return map { Net::Google::PicasaWeb::Photo->new($_, $self); } $self->_get_feed->entries;
}

# Implement uploading a new photo as described here:
# http://code.google.com/support/bin/answer.py?answer=63316&topic=10973
# http://code.google.com/apis/picasaweb/gdata.html#Add_Photo
# INPUT: filepath - path to photo to upload
#        opts: optional hash with the following keys:
#           description - description of photo
#           progress    - coderef to callback($stage, $sent, $total, $userdata)
#           userdata    - user data passed to callback
#           headers     - HTTP::Headers or array ref to overwrite headers
sub add_photo {
    my ($self, $filepath, $opts) = @_;

    # Must have at least a filename
    croak 'Usage: $album->upload_photo($filename, \%opts)' if @_ < 2;
    croak qq(Can't find file '$filepath'.) unless -f $filepath and -r _;
    my $filename = fileparse($filepath);

    # Opts must be a hash ref
    $opts = {} unless defined $opts;
    croak q(opts must be a hash ref.) unless ref($opts) eq 'HASH';

    # Pre-requsites
    croak q(Must be logged in to upload.) unless $self->is_authenticated();

    # Allowed options and default values:
    my %options = (
        description => q{},
        progress    => sub{ return 0; },
        userdata    => undef,
        headers     => undef,
    );

    # Check supplied options
    for (keys %{$opts}) {
        unless (exists $options{$_}) {
            carp qq(Ignoring unrecognised option '$_');
            delete $opts->{$_};
        }
    }

    # Apply supplied options
    %options = ( %options, %{$opts} );

    # Final check.
    croak q(option progress must be a code ref) unless ref($options{progress}) eq 'CODE';

    #################################
    # Step 1 perform the file upload:
    #################################

    # Create the request
    my $uri = $self->_get_uri_from_feed('post');
    my $req = HTTP::Request->new('POST', $uri);

    # Set Content-Type and Content-Encoding based on file
    guess_media_type($filepath, $req);

    # Set the Slug: header
    $req->header( Slug => $filename ); # TODO: should we worry about non-acsii chars?

    # User override of headers:
    $req->header( $options{headers} ) if defined $options{headers};

    # Set Content-Length header
    my $filesize = (stat $filepath)[7];
    $req->header( Content_Length => $filesize );

    # Next code creates a callback for passing chunks of the
    # request content to the request. This saves us having to
    # slurp the whole file into memory.

    # Ensure we can open the file for reading.
    open my $fh, '<', $filepath or die qq(Failed to open '$filepath': $^E);
    # It's binary data!
    binmode $fh;

    my $sent       = 0;   # to hold bytes sent so far
    my $speed      = 0;   # to hold current speed of transfer
    my $abort      = 0;   # Whether to abort or not
    my $start_time = time;

    my $code = $options{progress};
    my $userdata = defined $options{userdata} ? $options{userdata} : q{};

    $code->('begin', $sent, $filesize, $userdata);

    $req->content( sub {
        # Hook to provide progress callback to user

        my $remaining = $filesize - $sent;
        my $elapsed   = time - $start_time;
        my $speed     = $elapsed == 0 ? 0 : ($sent * 8) / $elapsed; # Avoid div by 0

        if( $code->('upload', $sent, $filesize, $userdata) ) {
            # ABORT upload
            $abort = 1;
            $code->('aborting', $sent, $filesize, $userdata);
            return q{};
        }

        # Read the next chunk of data
        my $r = sysread $fh, my $buf, guess_block_size($remaining, $speed); # TODO shouldn't use remaining?

        if (!defined $r) { # ERROR
            die $!;
        }
        elsif ($r == 0) {  # EOF
            close $fh;
            return q{};
        }

        # Increment byte counter and return buffer to
        # UserAgent
        $sent += $r;
        return $buf;
    } );

    my $response = $self->_get_ua->request($req);

    if($abort) {
        $code->('aborted', $sent, $filesize, $userdata);
        $self->_set_last_error('User aborted upload');
        return;
    }

    if(!$response->is_success()) {
        $self->_set_last_error(
            qq(Failed to upload photo to '$uri'.  Server said:\n) .
            qq(---- Response Starts ----\n) .
            $response->as_string() .
            qq(----- Response Ends -----\n)
        );
        $code->('failed', $sent, $filesize, $userdata);
        return;
    }

    $code->('uploaded', $sent, $filesize, $userdata);

    my $atom = $response->content();
    my $new_entry = XML::Atom::Entry->new(\$atom);
    my $new_photo = Net::Google::PicasaWeb::Photo->new($new_entry, $self);

    #################################
    # Step 2: upload the metadata
    #################################

    $code->('metadata', $sent, $filesize, $userdata);

    my $result = $new_photo->update_info( {
        title   => $filename,
        summary => $options{description},
    } );

    unless (defined $result) {
        $self->_set_last_error(
            qq(Failed to update photo info.\n) .
            $new_photo->_get_last_error
        );
        $code->('failed', $sent, $filesize, $userdata);
        return;
    }

    $code->('done', $sent, $filesize, $userdata);

    return $new_photo;
}

## This code implement the multiprt upload described at:
#  http://code.google.com/apis/picasaweb/gdata.html#Add_Photo
#sub multipart_upload_photo {
#    my ($self, $filepath, $description) = @_;
#
#    croak qq(Can't find file '$filepath'.) unless -f $filepath;
#    croak qq(Must be logged in to upload.) unless $self->{user}->is_authenticated();
#    $description |= "";
#    
#    my @links = $self->{entry}->link();
#
#    my $photo_post_url;
#
#    for my $link (@links) {
#        if ( $link->rel() eq FEED_LINK_REL ) {
#            $photo_post_url = $link->href();
#            last;
#        }
#    }
#    die q(No album post <link> found) unless $photo_post_url;
#
#    my $filename = fileparse($filepath);
#
#    ### Create the multipart/related POSt as described at:
#    #   http://code.google.com/apis/picasaweb/gdata.html#Add_Photo
#
#    ## Part 1 - entry
#    my $entry = XML::Atom::Entry->new(Version => '1.0');
#    $entry->title($filename);
#    $entry->summary($description);
#    my $category = XML::Atom::Category->new(Version => '1.0');
#    $category->scheme('http://schemas.google.com/g/2005#kind');
#    $category->term('http://schemas.google.com/photos/2007#photo');
#    $entry->category($category);
#
#    my $part1 = HTTP::Message->new( [ Content_Type => 'application/atom+xml' ], $entry->as_xml() );
#
#    ## Part 2 - image data
#    open my $fh, '<', $filepath or croak q(Can't open $filepath: $^E);
#    binmode $fh;
#    my $filedata = do { local $/; <$fh>; };
#    close $fh;
#
#    my $part2 = HTTP::Message->new( [ Content_Type => guess_media_type($filepath) ], $filedata );
#
#    my $request = HTTP::Request->new("POST", $photo_post_url);
#
#    $request->header(
#        'Content_Type' => 'multipart/related',
#        $self->{user}->get_auth_headers(),
#    );
#
#    $request->add_part($part1);
#    $request->add_part($part2);
#
#    my $r = $self->{user}->{ua}->request($request);
#    if(!$r->is_success()) {
#        die $r->as_string();
#    }
#
#    my $atom = $r->content();
#    my $new_entry = XML::Atom::Entry->new(\$atom);
#
#    return Net::Google::PicasaWeb::Photo->new($new_entry);
#}

1; # End of Album.pm
__END__

=pod

=cut
