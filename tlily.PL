@@PERL@@
# $Header: /data/cvs/tlily/tlily.PL,v 1.39 1998/06/01 02:19:54 neild Exp $

require 5.00307;

$TL_ETCDIR="@@ETCDIR@@";
$TL_LIBDIR="@@LIBDIR@@";
$TL_EXTDIR="@@LIBEXTDIR@@";
$debug=0;

use lib qw(@@LIBMODDIR@@);
BEGIN { $load_ui=1; }
use LC::Version;
use LC::Config;
use LC::UI;
use LC::Server;
use LC::Command;
use LC::User;
use LC::Client;
use LC::State;
use LC::StatusLine;
use LC::Extend;
use LC::Event;
use LC::SubClient;
$|=1;

if ( -f 'tlily.PL' ) {
    my @tstat = stat('tlily.PL');
    my @mstat = stat($0);
    if ($tstat[9] > $mstat[9]) {
	print "tlily.PL is newer than $0 -- rerun Build.PL.\n";
	exit;
    }
}

config_init();
ui_start();
cmd_init();

unless (-f $main::TL_LIBDIR."/tlily.global") {
    ui_output("***");
    ui_output(Text => "*** Uh-oh!  No global config file found -- there is p
robably something wrong with your installation.",
              WrapChars => "*** ");
    ui_output("***");
}

statusline_init();

#$SIG{__DIE__} = sub { ui_output("DIE: " . $_[0]); };


$SIG{__WARN__} = \&sig_warn;
sub sig_warn {
    $SIG{__WARN__} = \&sig_warn;
    ui_output("WARNING: " . $_[0]);
}

$SIG{PIPE} = \&sig_pipe;
sub sig_pipe {
    $SIG{PIPE} = \&sig_pipe;
    my ($package, $filename, $line, $subroutine,
                  $hasargs, $wantarray, $evaltext, $is_require) = caller(1);

    ui_output("WARNING: Caught SIGPIPE. (from $package::$subroutine)");
}


my $int_active = 0;
$SIG{INT} = \&sig_int;
sub sig_int {
    $SIG{INT} = \&sig_int;
    if (!$int_active) {
	ui_output("(hit ctrl-c again within 5 seconds to exit)");
	$int_active = 1;
	register_timedhandler(Interval => 5,
			      Call => sub {
            $int_active = 0;
	    ui_output("(you waited too long to hit ctrl-c; exit aborted)");
	});
    } else {
	ui_end();
	exit;
    }
}


eval { main(); };
ui_end();
print STDERR $@ if ($@);


##############################################################################
sub main() {
    show_banner();
    
    load_extensions();

    ui_output("*** Connecting to $config{server} $config{port}.");
    server_connect($config{server}, $config{port});
    ui_output("*** Connected.");

    client_init();
    register_exithandler(\&client_exit);
    
    register_iohandler(Handle => \*STDIN,
		       Mode => 'r',
		       Name => 'b',
		       Call => sub { user_accept(); });

    while (1) {
	eval { event_loop(); };

	# Normal exit.
	if ($@ eq '') {
	    ui_output("*** Exiting.");
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
	die;
    }
}

sub client_exit() {
    if ($config{'exit_on_disconnect'}) {	
	ui_end();		
        exit;		
    }
    ui_output("*** Lost connection to server: hit enter to quit ***");
    register_eventhandler(Type => 'userinput',
			  Order => 'before',
			  Call => sub { ui_end(); exit; });
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
