use strict;
use warnings;

# Implements the API detailed at:
# http://code.google.com/apis/picasaweb/reference.html

package Net::Google::PicasaWeb::User;

our $VERSION = "0.00_01";
eval $VERSION;

use Net::Google::PicasaWeb::ClientLogin();
use Net::Google::PicasaWeb::Namespaces();
use Net::Google::PicasaWeb::Base();
use Net::Google::PicasaWeb::Album();
use Net::Google::PicasaWeb::Utils qw(format_bytes);

our @ISA = qw(Net::Google::PicasaWeb::Base);

use Carp qw(croak carp);
use URI();
use LWP::UserAgent();

######################################################################
# my $pw = Net::Google::PicasaWeb->new( $user, \%opts )
# Construct a new Net::Google::PicasaWeb object
# INPUT : Reference to hash.  Hash keys can be:
#           user (required) - user name (with or without domain)
#           password (optional) - user's password.
#           ua - LWP::UserAgent, or subclass
#  Both user and password are required for upload/write access and for
#  access to private (hidden) albums/photos.
# OUTPUT: returns a Net::Google::PicasaWeb object on success, croaks
#         on failure.
######################################################################
sub new {
    my ($class, $username, $opts) = @_;

    my $self = $class->SUPER::new();

    # Must have at least a user
    croak 'Usage: ' . __PACKAGE__ . '->new($username, \%opts)' if @_ < 2;
    croak qq($class->new must have a username) unless length($username) > 0;
    $self->_set_username($username);

    # Opts must be a hash ref
    $opts = {} unless defined $opts;
    croak q(opts must be a hash ref.) unless ref($opts) eq 'HASH';

    # Allowed options and default values:
    my %options = ( 
        password => undef, 
        ua       => undef,
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

    # Create or use supplied User Agent
    {
        my $ua;
        if(defined $options{ua} and $options{ua}->isa('LWP::UserAgent')) {
            $ua = $options{ua};
        }
        else {
            $ua = LWP::UserAgent->new();
        }
        $self->_set_ua($ua);
    }

    # Are we going to login?
    if(defined $options{password} and length $options{password} > 0) {
       return unless $self->login($options{password});
    }

    # Set up a dummy entry - allows us to use the generic routines
    my $dummy = XML::Atom::Entry->new(Version => '1.0');

    my @link_info = (
        { rel  => "http://schemas.google.com/g/2005#feed",
          type => "application/atom+xml",
          href => "http://picasaweb.google.com/data/feed/api/user/$username" },
        { rel  => "http://schemas.google.com/g/2005#post",
          type => "application/atom+xml",
          href => "http://picasaweb.google.com/data/feed/api/user/$username" },
        { rel  => "alternate",
          type => "text/html",
          href => "http://picasaweb.google.com/$username" },
        { rel  => "self",
          type => "application/atom+xml",
          href => "http://picasaweb.google.com/data/feed/api/user/$username" },
    );

    for my $link_info (@link_info) {
        my $link = XML::Atom::Link->new(Version => '1.0');
        $link->rel($link_info->{rel});
        $link->type($link_info->{type});
        $link->href($link_info->{href});

        $dummy->add_link($link);
    }

    $self->_set_entry($dummy);

    return $self;
}

sub login {
    my ($self, $password) = @_;

    # Must have a password
    croak 'Usage: $user->login($password)' if @_ < 2;
    croak q(Missing password) unless length($password) > 0;

    my $cli = Net::Google::PicasaWeb::ClientLogin->login(
        $self->_get_username,
        $password,
        { ua => $self->_get_ua },
    );

    unless (defined $cli) {
        $self->_set_last_error($Net::Google::PicasaWeb::ClientLogin::LastError);
        return;
    }

    $self->_set_cli($cli);

    return 1;
}

sub quotalimit        { $_[0]->_get_feed->gphoto->quotalimit; }
sub quotacurrent      { $_[0]->_get_feed->gphoto->quotacurrent; }
sub maxPhotosPerAlbum { $_[0]->_get_feed->gphoto->maxPhotosPerAlbum; }

sub describe {
    my ($self) = @_;

    print "User information for user '", $self->_get_username, "'.\n";

    if($self->is_authenticated()) {
        print "  Logged in.\n";
        print "  Using ", format_bytes($self->quotacurrent()), " of ",
            format_bytes($self->quotalimit()), ".\n";
        print "  Maximum of ", $self->maxPhotosPerAlbum(), " photos per album.\n";
    }
    else {
        print "  Not logged in.\n";
    }

    return 1;
}

sub is_authenticated {
    my ($self) = @_;

    my $cli = $self->_get_cli;
    return defined $cli and $cli->is_valid();
}

sub get_albums {
    my ($self) = @_;

    return map { Net::Google::PicasaWeb::Album->new($_, $self); } $self->_get_feed->entries;
}

sub add_album {
    my ($self, $opts) = @_;

    # Opts must be a hash ref
    $opts = {} unless defined $opts;
    croak q(opts must be a hash ref.) unless ref($opts) eq 'HASH';

    # Pre-requsites
    croak qq(Must be logged in to update) unless $self->is_authenticated();

    # Allowed options and default values:
    my %options = ( 
        title       => undef, 
        timestamp   => time, 
        description => undef,
        location    => undef,
        private     => 0,
        
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

    # Check opts

    # Create <entry> for photo
    my $entry = XML::Atom::PicasaEntry->new();
    $entry->title($options{title});
    $entry->summary($options{description});
    my $gphoto = XML::Atom::Gphoto->new();
        $gphoto->location($options{location});
        $gphoto->access($options{private} ? 'private' : 'public');
        $gphoto->commentingEnabled('true');
        $gphoto->timestamp($options{timestamp} * 1000);
    $entry->gphoto($gphoto);
        my $category = XML::Atom::Category->new();
        $category->scheme('http://schemas.google.com/g/2005#kind');
        $category->term('http://schemas.google.com/photos/2007#album');
    $entry->category($category);

    my $new_entry = $self->_add_entry_to_feed($entry);

    return unless $new_entry;
    return Net::Google::PicasaWeb::Album->new($new_entry, $self);
}

1; # End of User.pm
