@@PERL@@

$TL_EXTDIR="@@LIBEXTDIR@@";
$debug=0;

use lib qw(@@LIBMODDIR@@);
use LC::version;
use LC::log; 
use LC::config;
use LC::UI;
use LC::Server;
use LC::parse;
use LC::Command;
use LC::User;
use LC::State;
use LC::StatusLine;
use LC::Extend;
use LC::Event;
use Socket;
use Fcntl;
use IO::Select;
use Curses;
use POSIX;
$|=1;

# globals
#$have_pseudo=0;
#$last_alarm=0;
#$next_alarm=0;
#$wakeup=10;     # how often to exit the select loop to do status processing,
                # etc.
#$password_mode=0;

## main ##


LC::config::init();
ui_start();
cmd_init();

ui_attr('sender','bold');
ui_attr('dest','bold');
ui_attr('b','bold');
if (! $config{mono}) {
    ui_attr('status_line',  'fg:yellow',  'bg:blue',  'bold');
    ui_attr('input_line',   'fg:white',   'bg:black');
    ui_attr('text_window',  'fg:white',   'bg:black', 'normal');
    ui_attr('privhdr',      'fg:green',   'bg:black');
    ui_attr('privmsg',      'fg:green',   'bg:black');
    ui_attr('pubhdr',       'fg:cyan',    'bg:black');
    ui_attr('pubmsg',       'fg:white',   'bg:black');
    ui_attr('emote',        'fg:cyan',    'bg:black');
    ui_attr('review',       'fg:magenta', 'bg:black');
    ui_attr('usersend',     'fg:red',     'bg:black');
    ui_attr('whiteblue',    'fg:white',   'bg:blue');
    ui_attr('greenblue',    'fg:green',   'bg:blue',  'bold');
    ui_attr('yellow',       'fg:yellow',  'bg:black',  'bold');
    ui_attr('green',        'fg:green',   'bg:black',  'bold');
} else {
    ui_attr('status_line', 'reverse');
}

statusline_init();

my $state;

#$SIG{__DIE__} = sub { ui_output("DIE: " . $_[0]); };
$SIG{__WARN__} = sub { ui_output("WARNING: " . $_[0]); };

main();


##############################################################################
sub eventloop() {
    my $s = IO::Select->new($server_sock, \*STDIN);

    while (1) {
	foreach ($s->can_read()) {
	    if ($_ == $server_sock) {
		parse(server_read());
	    } elsif ($_ == \*STDIN) {
		user_accept();
	    }
	}
    }
}


sub init_connection_handling() {
    my $state = 'login';
    my $set_opts = 0;

    register_eventhandler(Call => sub {
	my($event,$handler) = @_;
	my $os = $state;
	if (($event->{Type} eq 'userinput') && ($state eq 'password')) {
	    $state = 'login';
	    $event->{ToUser} = 0;
	    ui_password(0);
	    user_password(0);
	} elsif (($event->{Type} eq 'userinput') && ($state eq 'blurb')) {
	    $state = 'cxna';
	} elsif (($event->{Type} eq 'userinput') && ($state eq 'reviewp')) {
	    $state = 'almostconnected';
	} elsif (($event->{Type} eq 'prompt') &&
		 ($event->{Text} =~ /^login:/)) {
	    set_client_options() unless ($set_opts);
	    $set_opts = 1;
	} elsif (($event->{Type} eq 'prompt') &&
		 ($event->{Text} =~ /^password:/)) {
	    $state = 'password';
	    ui_password(1);
	    user_password(1);
	} elsif (($event->{Type} eq 'prompt') &&
		 ($event->{Text} =~ /^-->/)) {
	    $state = 'blurb';
		set_client_options();
	} elsif (($state eq 'cxna') &&
		 ($event->{Type} eq 'serverline') &&
		 ($event->{Text} =~ /^Welcome to/)) {
	    $state = 'cxnb';
	} elsif (($state eq 'cxnb') &&
		 ($event->{Type} eq 'serverline')) {
	    $state = 'cxnc';
	} elsif (($state eq 'cxnc') &&
		 ($event->{Type} eq 'serverline') &&
		 ($event->{Text} =~ /\(Y\/n\)/)) {
	    $state = 'reviewp';
	} elsif (($state eq 'cxnc') &&
		 ($event->{Type} eq 'serverline')) {
	    $state = 'connected';
	} elsif ($event->{Type} eq 'connected') {
	    $state = 'connected';
	} elsif (($state eq 'almostconnected') &&
		 ($event->{Type} eq 'serverline')) {
	    $state = 'connected';
	}
	if ($state eq 'connected') {
	    deregister_handler($handler->{Id});
    	set_client_options();
		dispatch_event({Type => 'connected',
	               Text => '%connected unknown'});
	}
	return 0;
    });
}


sub set_client_options() {
    #
    # Lily is gifted with a multitude of incompatible options.  What I have
    # here seems to work everywhere in use at the moment.  Someday, someone
    # will come along and break everything in the name of progress.  At this
    # point, I will declare lily dead, and get a life.
    #
    # The single, sole option which appears to work everywhere is `leaf'.
    # This gives me command leafing; the server will kindly identify
    # exactly what lines it sends to me are associated with what commands
    # I send to it.  This is insanely useful; I'm amazed it works.  (I had
    # begun to think that the server designers had intentionally designed
    # things to prevent anything useful from being usable.)
    #
    # But, alas, there is a serpent in paradise.  Nobody (and I mean NOBODY)
    # other than lclient is allowed to receive %gs.  This means that signalling
    # is utterly broken by my use of this option.  I therefore shall
    # implement signalling entirely in the client, and to hell with the
    # servers.
    #
    # Another REALLY useful option is `leaf-msg'.  It doesn't work right on
    # 2.2a1 cores.
    #
    # And then there's the `connected' option!  Ah, what I wouldn't do to
    # be able to use IT!
    #

    server_send("\#\$\# client_version $TL_VERSION\n");
    server_send("\#\$\# client_name TigerLily\n");
    server_send("\#\$\# options +leaf-all +leaf +connected\n");
}


sub main() {
    show_banner();
    
    dotfile_init();
    load_extensions();

    log_notice("Connecting to $config{server} $config{port}.");
    server_connect($config{server}, $config{port});
    log_notice("Connected.");

    init_connection_handling();

    register_iohandler(Handle => $server_sock,
		       Mode => 'r',
		       Name => 'a',
		       Call => sub { parse(server_read()); });
    register_iohandler(Handle => \*STDIN,
		       Mode => 'r',
		       Name => 'b',
		       Call => sub { user_accept(); });

    while (1) {
	eval { event_loop(); };

	# Normal exit.
	if ($@ eq '') {
	    log_notice("Exiting.");
	    ui_end();
	    exit;
	}

	# Non-fatal errors.
	if ($@ =~ /^Undefined subroutine/) {
	    my $l = $@; $l =~ s/\\\</\\$@/g; chomp($l);
	    ui_output "<yellow>ERROR: $l</yellow>";
	    next;
	}
	
	# Oh, well.  Guess we have a problem.
	ui_end();
	die $@;
    }
}


sub dotfile_init() {
    if ( -f "$ENV{HOME}/.lily/lclient/autologin" ) {
	#rpi lily.acm.rpi.edu 7777 user password
	my $f=new FileHandle("<$ENV{HOME}/.lily/lclient/autologin");
	if (defined $f) {
	    log_notice("Loading config from ~/.lily/lclient/autologin");
	    my ($l)=grep /\S/, grep ! /^\s*\#/, <$f>;
	    $l=~s/^\s*//g;
	    ($config{site},$config{server},$config{port},
	     $config{login},$config{password})=split /\s+/,$l;
	}
	
    }
    
    # The init file should be used to configure the various extensions that 
    # have been loaded.
    if ( -f "$ENV{HOME}/.lily/tlily/init" ) {
	log_notice("Loading config from ~/.lily/tlily/init");
	extension("$ENV{HOME}/.lily/tlily/init");
    } else {
	log_notice("(You may add perl code in ~/.lily/tlily/init)");
    }
}


sub show_banner() {

    ui_output(qq[
<yellow>     ("`-/")_.-'"``-._ </yellow>
<yellow>      . . `; -._    )-;-,_`)</yellow>          <green>TigerLily $TL_VERSION</green>
<yellow>     (v_,)'  _  )`-.\  ``-'</yellow>             <b>"Feel Free"</b>
<yellow>    _.- _..-_/ / ((.'</yellow>
<yellow>  ((,.-'   ((,/ </yellow>
<b>------------------------------------------------------------------------------</b>
]);
}


1;
