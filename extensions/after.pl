
register_user_command_handler('after', \&after_handler);
register_help_short('after', "Run a lily command after a delay");
register_help_long('after', qq(Usage: %after (time) (command)
*
* Runs (command) after (time).
* time can be:
*       N        N seconds
*       Ns       N seconds
*       Nm       N minutes
*       Nh       N hours
*       Nd       N days
));


# %after handler
sub after_handler {
    my($args) = @_;
    my(@F);
    $args =~ m/^\s*(\d+[hms]?)\s+(.*?)\s*$/;
    @F = ($1,$2);
    my $T;
    if($F[0] =~ m/^(\d+)s?$/) {
	$T = $1;
    }
    elsif($F[0] =~ m/^(\d+)m$/) {
	$T = $1 * 60;
    }
    elsif($F[0] =~ m/^(\d+)h$/) {
	$T = $1 * 3600;
    }
    else {
	ui_output("Usage: %after (time) (command)");
	return 0;
    }
    ui_output("time = $T");
    register_timedhandler(Interval => $T,
                          Repeat => 0,
                          Call => sub {
				ui_output("($F[0] of time have passed, running '$F[1]'.)");
				dispatch_event({Type => 'userinput',
					Text => $F[1]});
			});
    ui_output("(After $F[0] of time, I will run '$F[1]'.)");
    return 0;
}

1;
