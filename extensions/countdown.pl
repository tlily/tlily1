# $Header: /data/cvs/tlily/extensions/countdown.pl,v 2.1 1998/06/12 08:56:29 albert Exp $
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

    if($config{countdown_fmt}) {
	my($days,$hrs,$mins,$secs,$rem);
	$rem = $r;
	$days = int($rem / (60*60*24));
	$rem = int($rem % (60*60*24));
	$hrs = int($rem / (60*60));
	$rem = int($rem % (60*60));
	$mins = int($rem / (60));
	$rem = int($rem % (60));
	$secs = int($rem);
	#ui_output("$days/$hrs/$mins/$secs");
	my $str = $config{countdown_fmt};
	#ui_output($str);

	if($days > 0) { $str =~ s/\%\{(\d*)d(.*?)\}/sprintf("%$1d",$days).$2/e; }
	else { $str =~ s/\%\{(\d*)d.*?\}//; }
	#ui_output($str);

	if($hrs > 0) { $str =~ s/\%\{(\d*)h(.*?)\}/sprintf("%$1d",$hrs).$2/e; }
	else { $str =~ s/\%\{(\d*)h.*?\}//; }
	#ui_output($str);

	if($mins > 0) { $str =~ s/\%\{(\d*)m(.*?)\}/sprintf("%$1d",$mins).$2/e; }
	else { $str =~ s/\%\{(\d*)m.*?\}//; }
	#ui_output($str);

	if($interval_c eq 's' && $secs > 0) {
	    $str =~ s/\%\{(\d*)s(.*?)\}/sprintf("%$1d",$secs).$2/e;
	} else {
	    $str =~ s/\%\{(\d*)s.*?\}//;
	}
	#ui_output($str);
	$timer = $str;
    }
    else {
	$timer = $u . $interval_c;
    }
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
	$interval_c = 'd';
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
