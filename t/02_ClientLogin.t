#!perl -w
use strict;
use warnings;

######################################################################
# TODO
######################################################################

use lib qw( t );
use Test::More;
use LWP();
use Net::Google::PicasaWeb::ClientLogin();

$|++; # Autoflush 

######################################################################
# User configuration
my $VERBOSE = 0;

# If $real_username and $real_password are supplied, they should be
# the credentials for a valid account.  If provided, then a small
# number of the test are performed against the real Google
# ClientLogin server.
my $real_username = '';
my $real_password = '';
my $server_url    = $ENV{TEST_SERVER_URL};

######################################################################
######################################################################

######################################################################
# Start the server

my $server;
unless ($server_url) {
    diag qq(Starting Server ...) if $VERBOSE;
    require 'TestServer.pmt';
    $server = TestServer->new;
    $server->configure('ClientLogin');
    $server_url = $server->spawn();
    diag qq(Server listenting at $server_url) if $VERBOSE;
}

# Is the server running?
{
    my $ua = LWP::UserAgent->new();
    my $response = $ua->get($server_url);
    die "Looks like the server isn't running" unless $response->code == 404;
}

######################################################################
# Allow us to override the ClientLogin URL
{
    my $real_login_url = $Net::Google::PicasaWeb::ClientLogin::ClientLoginUrl;

    sub set_login_url {
        my ($url) = @_;

        my $base = "${server_url}ClientLogin/";

        $Net::Google::PicasaWeb::ClientLogin::ClientLoginUrl =
        (defined $url and length($url) > 0) ? $base . $url
                                            : $real_login_url;

        return;
    }
}

######################################################################
# Set up some parameters to be used for the tests
my %users = (
    # NAME: anything.
    # OK: whether we expect a login to be successful or not
    # PATH:
    #   error/errorType errorType is one of:
    #     BadAuthentication NotVerified TermsNotAgreed CaptchaRequired
    #     Unknown AccountDeleted AccountDisabled ServiceDisabled
    #     ServiceUnavailable
    #   good - login will succeed
    #   bad  - login will fail
    #   '' (empty string, identifies a real user account and tests will
    #      be performed against the real server)
    #NAME      USER     PASSWORD  OK  PATH
    bad   => [ 'bad'  , '12345' , 0, 'bad'                     ],
    error => [ 'error', 'abcd'  , 0, 'error/BadAuthentication' ],
    good  => [ 'good' , '12ab34', 1, 'good'                    ],
);

if (length($real_username) > 0 and length($real_password) > 0) {
    $users{real} = [ $real_username, $real_password, 1, '' ];
}

my @ok_users = grep { $users{$_}->[2] } keys %users;

my @errors = qw( BadAuthentication NotVerified TermsNotAgreed
                 CaptchaRequired Unknown AccountDeleted AccountDisabled
                 ServiceDisabled ServiceUnavailable );

######################################################################
# Plan tests
my $tests = 1;                        # public interface
$tests += (2 * scalar keys %users);   # Basic Interface
$tests += (6 * @ok_users);            # (re)login and auth token management
$tests += 22;                         # login parameters
$tests += 3;                          # adding @gmail.com to username
$tests += 5;                          # exercise _login()
$tests += 6;                          # exercise set_auth_headers()
$tests += 6;                          # exercise remove_auth_headers()
$tests += 3;                          # exercise get_auth_headers()
$tests += 3;                          # exercise get_auth_token()
$tests += 1;                          # exercise is_valid()
$tests += (3 * (@errors + 1));        # error messages from failed logins
$tests += 3;                          # garbage 403 error
$tests += 2;                          # server error

plan tests => $tests;

######################################################################
# Finally get around to the tests themselves!
######################################################################

######################################################################
# Test the public interface exists
{
    can_ok('Net::Google::PicasaWeb::ClientLogin',
        qw(
            login
            set_auth_headers
            remove_auth_headers
            get_auth_headers
            get_auth_token
            is_valid
        )
    );
}

# Test Basic interface
{
    for my $user (keys %users) {

        set_login_url($users{$user}->[3]);

        $Net::Google::PicasaWeb::ClientLogin::LastError = '';
        my $cli = Net::Google::PicasaWeb::ClientLogin->login(
            $users{$user}->[0], $users{$user}->[1]
        );

        if (!defined $cli) {
            ok($users{$user}->[2] == 0, "Failure for user '$user'");
            diag $Net::Google::PicasaWeb::ClientLogin::LastError if $VERBOSE;
            ok(length($Net::Google::PicasaWeb::ClientLogin::LastError) > 0,
                'Error Message set');
        }
        else {
            ok($users{$user}->[2] == 1, "Success for user '$user'");
            ok(length($Net::Google::PicasaWeb::ClientLogin::LastError) == 0,
                'Error Message not set');
        }
    }
}

######################################################################
# Test successful (re)login, and that the auth token management works
for my $user (@ok_users) {

    set_login_url($users{$user}->[3]);

    my $cli = Net::Google::PicasaWeb::ClientLogin->login(
        $users{$user}->[0], $users{$user}->[1]
    );

    ok(defined $cli, 'Successful Login');
    ok($cli->is_valid(), "Auth token valid");

    {
        # Check that auth token doesn't get renewed
        my $expires = $cli->{auth_expires};
        ok( ($cli->is_valid() and $cli->{auth_expires} == $expires),
            "Auth token valid and not renewed");
    }

    {
        # Invalidate auth token and see if we can logged in again
        $cli->{auth_expires} = time - 1000; # in the past
        ok( ($cli->is_valid() and $cli->{auth_expires} > time),
            "Auth token renewed");
    }

    {
        # Make the auth token expire within the retry time
        my $expires = time + Net::Google::PicasaWeb::ClientLogin::AUTH_RETRY_TIME() - (30 * 60);
        $cli->{auth_expires} = $expires;
        ok( ($cli->is_valid() and $cli->{auth_expires} > $expires),
            "Auth token renewed");
    }

    {
        # Check the UA has default headers that we are expecting
        my $headers = $cli->{ua}->default_headers;
        my $auth = $headers->header('Authorization');
        like($auth, qr/^GoogleLogin auth=[^\s]+$/,
            "Authorization header has correct form");
    }
}

######################################################################
# Testing for login parameters:
{
    my $user = 'test';
    my $password = '1234';
    set_login_url('good');

    {
        # No params
        my $cli = eval{ Net::Google::PicasaWeb::ClientLogin->login(); };
        my $error = $@;
        ok(!defined $cli, "No username or password");
        ok($error, "Error generated");
        chomp $error;
        like($error, qr/^usage/i, $error);
    }

    {
        # User only
        my $cli = eval{
            Net::Google::PicasaWeb::ClientLogin->login(
                $user
            );
        };
        my $error = $@;
        ok(!defined $cli, "No password");
        ok($error, "Error generated");
        chomp $error;
        like($error, qr/^usage/i, $error);
    }

    {
        # User empty
        my $cli = eval{
            Net::Google::PicasaWeb::ClientLogin->login(
                '', $password
            );
        };
        my $error = $@;
        ok(!defined $cli, "Empty user");
        ok($error, "Error generated");
        chomp $error;
        like($error, qr/^missing user/i, $error);
    }

    {
        # Password empty
        my $cli = eval{
            Net::Google::PicasaWeb::ClientLogin->login(
                $user, ''
            );
        };
        my $error = $@;
        ok(!defined $cli, "Empty password");
        ok($error, "Error generated");
        chomp $error;
        like($error, qr/^missing password/i, $error);
    }
    
    {
        # opts must be a hash ref;
        my $cli = eval{
            Net::Google::PicasaWeb::ClientLogin->login(
                $user, $password, 1
            );
        };
        my $error = $@;
        ok(!defined $cli, "Opts not a hash");
        ok($error, "Error generated");
        chomp $error;
        like($error, qr/hash ref/i, $error);
    }

    {
        # Check for bad opts
        my @warnings;
        local $SIG{__WARN__} = sub {
            my ($warning) = @_;
            chomp $warning;
            push @warnings, $warning;
        };

        my %bad_opts = (
            bad1 => 3,
            bad2 => 4,
        );

        my $cli = Net::Google::PicasaWeb::ClientLogin->login(
            $user, $password,
            {
                service     => 'lh2',
                source => Net::Google::PicasaWeb::ClientLogin::APP_NAME(),
                accountType => 'GOOGLE',
                ua          => LWP::UserAgent->new(),
                %bad_opts,
            }
        );
        pass("Bad options didn't croak");
        ok( (@warnings == keys %bad_opts), "Each bad options generated a warning");
        diag join("\n", @warnings) if $VERBOSE;

        my $re = join('|', keys %bad_opts);

        ok( ( (grep { $_ =~ m/$re/ } @warnings) == @warnings),
            "Each bad option reported once");
    }

    { # check using a bad useragent - unblessed
        my $ua = LWP::UserAgent->new();
        eval { Net::Google::PicasaWeb::ClientLogin->login($user, $password, { ua => 1 }); };
        my $error = $@;
        ok($@, "Bad UA gives error");
        like($@, qr/LWP::UserAgent/, "Error message talks about UA");
    }

    { # check using a bad useragent - blessed incorrectly
        my $ua = LWP::UserAgent->new();
        eval { Net::Google::PicasaWeb::ClientLogin->login($user, $password, { ua => bless {}, 'A' }); };
        my $error = $@;
        ok($@, "Bad UA gives error");
        like($@, qr/LWP::UserAgent/, "Error message talks about UA");
    }
}


######################################################################
# Exercise branch that adds @gmail.com to username
{
    set_login_url("user");

    my @users = (
        [ 'rob'            , 1 ],
        [ 'rob@gmail.com'  , 0 ],
        [ 'rob@example.com', 0 ],
    );

    for my $u (@users) {
        my $user = $u->[0];
        my $add_gmail = $u->[1];

        my $cli = Net::Google::PicasaWeb::ClientLogin->login($user, 'password');
        my $error = $Net::Google::PicasaWeb::ClientLogin::LastError;

        my $email = $user;
        $email .= '@gmail.com' if $add_gmail;
        my $re = "/User=$email=/";

        like($error, $re, "Exact email match for $email");
    }
}

######################################################################
# Exercise possible errors calling _login()
{
    set_login_url('good');

    {
        my $cli = Net::Google::PicasaWeb::ClientLogin->login('user', 'password');

        ok(defined $cli, 'Successful Login');

        # remove credentials and try to re-login
        delete $cli->{credentials};
        eval { $cli->_login(); };
        like($@, qr/No Credentials/i, "Login with no credentials");
    }

    {
        my $cli = Net::Google::PicasaWeb::ClientLogin->login('user', 'password');

        ok(defined $cli, 'Successful Login');

        # remove ua and try to re-login
        delete $cli->{ua};
        eval { $cli->_login(); };
        like($@, qr/No UserAgent/, "Login with no UserAgent");
    }

    set_login_url('noauthtoken');

    {
        eval { Net::Google::PicasaWeb::ClientLogin->login('user', 'password'); };

        like($@, qr/extract auth token/i, 'No Auth Token in response from server');
    }
}

######################################################################
# Exercise set_auth_headers()
{
    set_login_url('good');

    {
        # called as class method
        eval { Net::Google::PicasaWeb::ClientLogin::set_auth_headers(); };
        like($@, qr/^Usage/i, "set_auth_headers called as class method");
    }

    {
        my $cli = Net::Google::PicasaWeb::ClientLogin->login('user', 'password');

        # Called with a scalar non-ua parameter
        eval { $cli->set_auth_headers('1'); };
        like($@, qr/LWP::UserAgent/, "set_auth_headers called with non-ua parameter");
    }

    {
        my $cli = Net::Google::PicasaWeb::ClientLogin->login('user', 'password');

        # Called with a blessed non-ua parameter
        eval { $cli->set_auth_headers( bless({}, 'A')); };
        like($@, qr/LWP::UserAgent/, "set_auth_headers called with non-ua parameter");
    }

    {
        my $cli = Net::Google::PicasaWeb::ClientLogin->login('user', 'password');

        # no ua at all
        delete $cli->{ua};
        eval { $cli->set_auth_headers(); };
        like($@, qr/UserAgent/, "set_auth_headers called with non-ua parameter");
    }

    {
        my $cli = Net::Google::PicasaWeb::ClientLogin->login('user', 'password');

        # user defined ua
        my $ua = LWP::UserAgent->new();
        $cli->set_auth_headers($ua);
        my $value = $ua->default_headers->header('Authorization');
        like($value, qr/GoogleLogin auth=.+/, "set_auth_headers sets headers");
    }

    {
        my $cli = Net::Google::PicasaWeb::ClientLogin->login('user', 'password');

        # auth token invalid, and fails re-login
        set_login_url('bad');
        $cli->{auth_expires} = time - 1000; # in the past
        my $r = $cli->set_auth_headers();
        ok(!defined $r, "set_auth_headers returns undefined if authorization invalid");
    }
}


######################################################################
# Exercise remove_auth_headers()
{
    set_login_url('good');

    {
        # called as class method
        eval { Net::Google::PicasaWeb::ClientLogin::remove_auth_headers(); };
        like($@, qr/^Usage/i, "remove_auth_headers called as class method");
    }

    {
        my $cli = Net::Google::PicasaWeb::ClientLogin->login('user', 'password');

        # Called 'normally'
        $cli->remove_auth_headers();
        my $value = $cli->{ua}->default_headers->header('Authorization');
        ok(!defined $value, "remove_auth_headers removes header");
    }

    {
        my $cli = Net::Google::PicasaWeb::ClientLogin->login('user', 'password');

        # Called with a scalar (unblessed) non-ua parameter
        eval { $cli->remove_auth_headers('1'); };
        like($@, qr/LWP::UserAgent/, "remove_auth_headers called with non-ua parameter");
    }

    {
        my $cli = Net::Google::PicasaWeb::ClientLogin->login('user', 'password');

        # Called with a blessed non-ua parameter
        eval { $cli->remove_auth_headers( bless({}, 'A')); };
        like($@, qr/LWP::UserAgent/, "remove_auth_headers called with non-ua parameter");
    }

    {
        my $cli = Net::Google::PicasaWeb::ClientLogin->login('user', 'password');

        # Called with external ua
        my $ua = LWP::UserAgent->new();
        $cli->set_auth_headers($ua);
        $cli->remove_auth_headers($ua);
        my $value = $ua->default_headers->header('Authorization');
        ok(!defined $value, "remove_auth_headers removes header (external ua)");
    }

    {
        my $cli = Net::Google::PicasaWeb::ClientLogin->login('user', 'password');

        # no ua at all
        delete $cli->{ua};
        eval { $cli->remove_auth_headers(); };
        like($@, qr/UserAgent/, "remove_auth_headers called with no ua");
    }
}

######################################################################
# Exercise get_auth_headers()
{
    set_login_url('good');

    {
        # called as class method
        eval { Net::Google::PicasaWeb::ClientLogin::get_auth_headers(); };
        like($@, qr/^Usage/i, "get_auth_headers called as class method");
    }

    {
        # get it to return undef (is_valid check fails)
        my $cli = Net::Google::PicasaWeb::ClientLogin->login('user', 'password');
        set_login_url('bad');
        $Net::Google::PicasaWeb::ClientLogin::LastError = '';
        $cli->{auth_expires} = time - 1000;
        my $r = $cli->get_auth_headers();
        ok(!defined $r, "get_auth_headers returns undef on failure");
        like($Net::Google::PicasaWeb::ClientLogin::LastError, qr/Internal/i, "Error correct");
    }
}

######################################################################
# Exercise get_auth_token()
{
    set_login_url('good');

    {
        # called as class method
        eval { Net::Google::PicasaWeb::ClientLogin::get_auth_token(); };
        like($@, qr/^Usage/i, "get_auth_token called as class method");
    }
    
    {
        # get it to return undef (is_valid check fails)
        my $cli = Net::Google::PicasaWeb::ClientLogin->login('user', 'password');
        set_login_url('bad');
        $Net::Google::PicasaWeb::ClientLogin::LastError = '';
        $cli->{auth_expires} = time - 1000;
        my $r = $cli->get_auth_token();
        ok(!defined $r, "get_auth_token returns undef on failure");
        like($Net::Google::PicasaWeb::ClientLogin::LastError, qr/Internal/i, "Error correct");
    }
}

######################################################################
# Exercise is_valid()
{
    set_login_url('good');

    {
        # called as class method
        eval { Net::Google::PicasaWeb::ClientLogin::is_valid(); };
        like($@, qr/^Usage/i, "is_valid called as class method");
    }
}

######################################################################
# Testing for failed login error messages (403) errors
{
    my $user = 'test';
    my $password = '1234';

    for my $error (@errors, "NON_EXISTANT") {
        set_login_url("error/$error");
        $Net::Google::PicasaWeb::ClientLogin::LastError = '';
        my $cli = Net::Google::PicasaWeb::ClientLogin->login($user, $password);

        ok(!defined $cli, "failed login: $error");
        ok(length $Net::Google::PicasaWeb::ClientLogin::LastError > 0, "Error message set");
        diag $Net::Google::PicasaWeb::ClientLogin::LastError if $VERBOSE;
        like($Net::Google::PicasaWeb::ClientLogin::LastError, "/$error/",
            "Error message contains error '$error'");
    }
}

######################################################################
# Testing for failed login error messages (403) errors, returning
# a garbage result (no Error= parameter)
{
    my $user = 'test';
    my $password = '1234';

    set_login_url("error/garbage");
    $Net::Google::PicasaWeb::ClientLogin::LastError = '';
    my $cli = Net::Google::PicasaWeb::ClientLogin->login($user, $password);

    ok(!defined $cli, "failed login: garbage");
    ok(length $Net::Google::PicasaWeb::ClientLogin::LastError > 0, "Error message set");
    diag $Net::Google::PicasaWeb::ClientLogin::LastError if $VERBOSE;
    like($Net::Google::PicasaWeb::ClientLogin::LastError, qr/Response Starts.*403/s,
            "Garbage 403 error");
}

######################################################################
# Testing for server failure
{
    my $user = 'test';
    my $password = '1234';

    set_login_url('bad');
    $Net::Google::PicasaWeb::ClientLogin::LastError = '';
    my $cli = Net::Google::PicasaWeb::ClientLogin->login($user, $password);
    my $error = $Net::Google::PicasaWeb::ClientLogin::LastError;

    ok(!defined $cli, "failed login");
    ok(length $error > 0, "Error message set");
    diag $error if $VERBOSE;
}
