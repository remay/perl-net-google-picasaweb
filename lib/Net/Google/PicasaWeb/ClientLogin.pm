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
# This module implements the Google ClientLogin API detailed at:
# http://code.google.com/apis/accounts/AuthForInstalledApps.html
######################################################################

package Net::Google::PicasaWeb::ClientLogin;

our ($VERSION) = q$Revision$ =~ m/(\d+)/xm;

use Carp qw(carp croak);
use LWP::UserAgent qw();
use Scalar::Util qw(blessed);
use Exporter qw(import);

our @EXPORT_OK = qw($LastError $ClientLoginUrl);

our $LastError      = q{};
our $ClientLoginUrl = 'https://www.google.com/accounts/ClientLogin';

sub APP_NAME() { 'Perl-' . __PACKAGE__ . "-$VERSION" }
sub AUTH_VALID_TIME() { 12 * 60 * 60 }    # 12 hours in seconds
sub AUTH_RETRY_TIME() { 4 * 60 * 60 }     # 4 hour in seconds

######################################################################
# login() - PUBLIC - Constructor method
#
# Net::Google::PicasaWeb::ClientLogin->login( $user, $password, \%opts );
# login to a google service (defaults to picasaweb, service 'lh2')
#
# INPUT:
# username - user's account name, domain '@gmail.com' added if no
#            domain provided.
# password - password for user account.
# options  - optional hash reference with the following allowed keys:
#            service    - Google APIs service name. Defaults to 'lh2'
#            source     - Identifies the source of the authentication
#                         request. Defaults to
#                         'Perl-Net::Google::PicasaWeb-$VERSION'
#            acountType - Identifies whether the account is a google
#                         account or a hosted account. Allowed values
#                         are: 'GOOGLE', 'HOSTED' and 'HOSTED_OR_GOOGLE'.
#                         Defaults to 'GOOGLE'.
#            ua         - user supplied LWP::UserAgent object, in case the
#                         user wants to set up specific options (e.g.
#                         proxies).  If not provided, then a LWP::UserAgent
#                         instance is created internally. On success adds
#                         an 'Authorization' header to the UserAgent's default
#                         headers.
#
# OUTPUT:
# On success returns a Net::Google::PicasaWeb::ClientLogin object.
# On failure returns a false value (undef) and sets
# $Net::GooglePicasaWeb::ClientLogin::LastError to a string containing
# an error message identifying the failure.
######################################################################
sub login {
    my ( $class, $user, $pass, $opts ) = @_;

    my $self = bless {}, $class;

    # Must have at least user and password
    croak 'Usage: ' . __PACKAGE__ . '->login($user, $password, \%opts)'
        if @_ < 3;
    croak q(Missing user name) if length($user) < 1;
    croak q(Missing password)  if length($pass) < 1;

    # User must have a domain
    if ( $user !~ m/@/xm ) {
        $user .= '@gmail.com';
    }

    # Opts must be a hash ref
    $opts ||= {};
    croak q(opts must be a hash ref.) if ref($opts) ne 'HASH';

    # Allowed options and default values:
    my %options = (
        service     => 'lh2',
        source      => APP_NAME,
        accountType => 'GOOGLE',
        ua          => LWP::UserAgent->new(),
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

    # Check options.  We don't check service, source, or
    # accountType, as we assume anyone using them has a clue.
    croak q(ua option must be a 'LWP::UserAgent' object (or a subclasss))
        if
        not( blessed $options{ua} and $options{ua}->isa('LWP::UserAgent') );

    # setup auth request
    $self->{ua} = $options{ua};

    # Store login credentials
    $self->{credentials} = {
        Email       => $user,
        Passwd      => $pass,
        service     => $options{service},
        source      => $options{source},
        accountType => $options{accountType},
    };

    return $self->_login() ? $self : ();
}

######################################################################
# _login() - PRIVATE method
#
# $self->_login();
# re-login to a google service using the stored credentials
#
# INPUT:
# none
#
# OUTPUT:
# On success returns a true value.
# On failure returns a false value (undef) and sets
# $Net::GooglePicasaWeb::ClientLogin::LastError to a string containing
# an error message identifying the failure.
######################################################################
sub _login {
    my ($self) = @_;

    # Ensure we have some credentials
    die q(No Credentials) if not defined $self->{credentials};

    # And a user agent
    die q(No UserAgent) if not defined $self->{ua};

    # Make the Authentication request
    my $response = $self->{ua}->post( $ClientLoginUrl, $self->{credentials} );

    # XXX perhaps $self->{last_response} = $response; would be useful for
    # debug?

    # Report errors
    if ( not $response->is_success() ) {
        $LastError = _generate_error_message($response);
        return;
    }

    # Extract Auth token from response
    my $c = $response->content();
    my ($auth) = $c =~ m/Auth=(.+)(\s+|$)/xm;
    die qq(Couldn't extract auth token from '$c') if not defined $auth;

    # store auth token
    $self->{auth} = $auth;

    # Store the time that this authentication will expire
    $self->{auth_expires} = time + AUTH_VALID_TIME;

    # Add the authorisation token to the User Agent's
    # default headers.
    $self->set_auth_headers();

    return 1;
}

######################################################################
# _generate_error_message() - PRIVATE function
#
# _generate_error_message( $response );
# Generate an error message suitable for user consumption, based on a
# failured HTTP request
#
# INPUT:
# response - An HTTP::Response object generated by a failed request to
#            the Google ClientLogin API.
#
# OUTPUT:
# Returns a string containing details of the error.
######################################################################
sub _generate_error_message {
    my ($response) = @_;

    # 403 responses from the ClientLogin service will contain an
    # Error=XXXX parameter in the body of the response.  XXXX is the
    # key of this hash.  The text is a modified version of the text
    # provided in the ClientLogin API documentation.
    my %reasons = (
        BadAuthentication =>
            'The login request used a username or password that is not recognized.',

        NotVerified =>
            'The account email address has not been verified. The user will need '
            . 'to access their Google account directly to resolve the issue before '
            . 'logging in using this non-Google application.',

        TermsNotAgreed =>
            'The user has not agreed to terms. The user will need to access their '
            . 'Google account directly to resolve the issue before logging in using '
            . 'this non-Google application.',

        CaptchaRequired => 'A CAPTCHA is required. Please visit '
            . 'https://www.google.com/accounts/DisplayUnlockCaptcha '
            . 'to unlock the account before trying to log in again.',

        Unknown =>
            'The error is unknown or unspecified; the request contained invalid '
            . 'input or was malformed.',

        AccountDeleted => 'The user account has been deleted.',

        AccountDisabled => 'The user account has been disabled.',

        ServiceDisabled =>
            'The user\'s access to this service has been disabled. (The user '
            . 'account may still be valid.)',

        ServiceUnavailable =>
            'The service is not available; try again later.',
    );

    my $code = $response->code();

    # Documented errors
    if ( $code == 403 ) {
        my $message = $response->message();
        my $content = $response->content();

        if ( $content =~ m/Error=(.+)(\s+|$)/xm ) {
            my $error  = $1;
            my $reason = $reasons{$error};
            $reason ||= "Unknown error type '$error'";

            return qq(Login Failed: $error: $reason [$message($code)]);
        }

        # Fall-through for any message that doesn't match what we
        # expected
    }

    # Unknown errors
    return qq(Login Failed for an unknown reason.  This is the response\n)
        . qq(received from the ClientLogin server:\n)
        . qq(-- Response Starts --\n)
        . $response->as_string()
        . qq(-- Response Ends --\n);
}

######################################################################
# set_auth_headers() - PUBLIC method
#
# $self->set_auth_headers( $ua );
# Set the default headers of the User Agent provided to the login()
# method, or to another user agent, if supplied, to include an
# 'Authorisation' header suitable for use with the Google service.
#
# INPUT:
# ua - An optional LWP::UserAgent object to set the headers on. If not
#      provided, set the headers on the user agent passed into or
#      created by the constructor.
#
# OUTPUT:
# On success returns a true value.
# On failure returns a false value (undef) and sets
# $Net::GooglePicasaWeb::ClientLogin::LastError to a string containing
# an error message identifying the failure.
# Failure will occur if the existing authorisation token has expired, and we
# fail to obtain a new one.
######################################################################
sub set_auth_headers {
    my ( $self, $ua ) = @_;

    croak q(Usage: $self->set_auth_headers($ua)) if @_ < 1;

    $ua ||= $self->{ua};
    croak q(ua must be a LWP::UserAgent (or a sub-class))
        if not( blessed $ua and $ua->isa('LWP::UserAgent') );

    # Check the auth token is valid
    return if not $self->is_valid();

    # Set the default headers
    $ua->default_headers()->header( $self->get_auth_headers() );

    return 1;
}

######################################################################
# remove_auth_headers() - PUBLIC method
#
# $self->remove_auth_headers( $ua );
# Remove the 'Authorization header frm the default headers of the User
# Agent provided to the login() method, or to another user agent, if
# supplied.
#
# INPUT:
# ua - An optional LWP::UserAgent object to remove the headers from.
#      If not provided, remove the headers from the user agent passed
#      into or created by the constructor.
#
# OUTPUT:
# Returns a true value.
######################################################################
sub remove_auth_headers {
    my ( $self, $ua ) = @_;

    croak q(Usage: $self->remove_auth_headers($ua)) if @_ < 1;

    $ua ||= $self->{ua};
    croak q(ua must be a LWP::UserAgent (or a sub-class))
        if not( blessed $ua and $ua->isa('LWP::UserAgent') );

    # Remove the Authorization header
    $ua->default_headers()->remove_header('Authorization');

    return 1;
}

######################################################################
# get_auth_headers() - PUBLIC method
#
# $self->get_auth_headers();
# Get the 'Authorization' header details
#
# INPUT:
# ua - An optional LWP::UserAgent object to set the headers on. If not
#      provided, set the headers on the user agent passed into or
#      created by the constructor.
#
# OUTPUT:
# On success returns a two item list.  The first item is the header name
# ('Authorization'), the second is the header value.
# On failure returns a false value (undef) and sets
# $Net::GooglePicasaWeb::ClientLogin::LastError to a string containing
# an error message identifying the failure.
# Failure will occur if the existing authorisation token has expired,
# and we fail to obtain a new one.
######################################################################
sub get_auth_headers {
    my ($self) = @_;

    croak q(Usage: $self->get_auth_headers()) if @_ < 1;

    # Check the auth token is valid
    return if not $self->is_valid();

    return ( Authorization => 'GoogleLogin auth=' . $self->get_auth_token() );
}

######################################################################
# get_auth_token() - PUBLIC method
#
# $self->get_auth_token();
# Get the Auth token string as returned by the ClientLogin Server
#
# INPUT:
# none.
#
# OUTPUT:
# On success returns a string containing the Auth token provided by
# the ClientLogin service.
# On failure returns a false value (undef) and sets
# $Net::GooglePicasaWeb::ClientLogin::LastError to a string containing
# an error message identifying the failure.
# Failure will occur if the existing authorisation token has expired,
# and we fail to obtain a new one.
######################################################################
sub get_auth_token {
    my ($self) = @_;

    croak q(Usage: $self->get_auth_token()) if @_ < 1;

    # Check the auth token is valid
    return if not $self->is_valid();

    return $self->{auth};
}

######################################################################
# is_valid() - PUBLIC method
#
# $self->is_valid();
# Check to see if the authorisation token assosiated with the
# Net::Google::PicassaWeb::ClientLogin object is still valid.
# If it is not, then the routine attempts to obtain a new one,
# and this method only returns false if that re-login attempt
# fails.
#
# Although it is expected that an Auth token will remain valid for
# 24 hours, this is not documented and so this module takes a
# conservative approach. It currently expires the token after 12 hours
# and starts attempting to get a new token 4 hours before that. Users
# of this module should call is_valid() periodically (at least
# once an hour is recommended, for future proofing), to ensure that
# any long-running process always has a valid token.
#
# If you are using a User Agent that was not passed to the constructor,
# then record the Time-To-Live (TTL) returned by this call, and on
# subsequent calls if the TTL increases then obtain the new Auth
# token or Authorization header.
#
# INPUT:
# none.
#
# OUTPUT:
# If the Auth token is still valid, or if it was renewed, returns a
# true value.  The value returned is the expect validity period of
# Auth token in seconds.
# On failure returns a false value (undef) and sets
# $Net::GooglePicasaWeb::ClientLogin::LastError to a string containing
# an error message identifying the failure.
# Failure will occur if the existing authorisation token has expired,
# and we fail to obtain a new one.
######################################################################
sub is_valid {
    my ($self) = @_;

    croak q(Usage: $self->is_valid()) if @_ < 1;

    my $ttl = $self->{auth_expires} - time;

    # (re)login if less than AUTH_RETRY_TIME seconds remains
    if ( $ttl < AUTH_RETRY_TIME ) {
        $self->_login();
    }

    # re-calculate ttl (we should have a new auth_expires
    # time if (re)login succeeded
    $ttl = $self->{auth_expires} - time;

    if ( $ttl < 0 ) {

        # We have expired, and failed to re-login
        return 0;
    }

    return $ttl;
}

1;    # End of ClientLogin.pm
__END__

=pod

=cut
