#
# Put a countdown timer on your status line.
#

my $end_t;
my $interval;
my $interval_c;
my $timer = '';
my $event_id;

sub set_timer {
    my $r = $end_t - time;
    my $u = int($r / $interval);
    $u ||= 1;

    if($r <= $interval) {
	if($interval == 60*60*24) {
	    $interval_c = 'h';
	    $interval = 60*60;
	    $u = int($r / $interval);
	}
	elsif($interval == 60*60) {
	    $interval_c = 'm';
	    $interval = 60;
	    $u = int($r / $interval);
	}
    }

    my $l = $r % $interval;

    if ($r <= 0) {
	$timer = '';
	undef $event_id;
	redraw_statusline();
	ui_bell();
	ui_output("(Timer has expired)");
	return 0;
    }

    $timer = $u . $interval_c;
    redraw_statusline();


    $event_id = register_timedhandler(Interval => $l || $interval,
				      Repeat => 0,
				      Call => \&set_timer);
    return 0;
}

sub countdown_cmd($) {
    my($args) = @_;

    if ($args eq 'off') {
	deregister_handler($event_id) if ($event_id);
	$timer = '';
	redraw_statusline();
	undef $event_id;
	return 0;
    }

    if ($args !~ /^(\d+)([dhms]?)$/) {
	ui_output("Usage: %countdown [\\<time> | off]");
	return 0;
    }

    if ($2 eq 'd') {
	$interval = 60 * 60 * 24;
	$interval_c = 'h';
    } elsif ($2 eq 'h') {
	$interval = 60 * 60;
	$interval_c = 'h';
    } elsif ($2 eq 'm') {
	$interval = 60;
	$interval_c = 'm';
    } else {
	$interval = 1;
	$interval_c = 's';
    }

    $end_t = time + ($1 * $interval);

    set_timer();
    return 0;
}


register_statusline(Var => \$timer,
		    Position => "PACKRIGHT");
register_user_command_handler('countdown', \&countdown_cmd);
register_help_short('countdown',
		    'Display a countdown timer on the status line');
register_help_long('countdown', <<END
Usage: %countdown <time>
       %countdown off

Displays a countdown timer on the status line.  The time may be specified in several ways:
      N        N seconds
      Ns       N seconds
      Nm       N minutes
      Nh       N hours
      Nd       N days

You may use "%countdown off" to cancel an existing countdown.
END
		   );
