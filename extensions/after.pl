
register_user_command_handler('after', \&after_handler);
register_help_short('after', "Run a lily command after a delay");
register_help_long('after', qq(Usage:
%after (time) (command)
Runs (command) after (time).

%after
List all pending afters.

%after cancel (id)
Cancel after #(id).

time can be:
      N        N seconds
      Ns       N seconds
      Nm       N minutes
      Nh       N hours
      Nd       N days
));

my %after;
my %after_id;
my %after_time;
my $id=0;

# %after handler
sub after_handler {
    my($args) = @_;
    my(@F);
    if($args eq '') {
	ui_output("Id\tTime\tCommand\n--\t----\t-------");
	my $k;
	foreach $k (keys %after) {
	    ui_output(sprintf("%2d\t%4s\t%s", $k, $after_time{$k}, $after{$k}));
	}
	return 0;
    }
	
    if($args =~ /cancel\s+(\d+)\s*$/) {
	my $tbc = $1;
	ui_output("(Cancelling afterid $tbc ($after{$tbc}))");
	deregister_handler($after_id{$tbc});
	delete $after{$tbc}; delete $after_id{$tbc}; delete $after_time{$tbc};
	return 0;
    }

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
    #ui_output("time = $T");
    $after{$id} = $F[1];
    $after_time{$id} = $F[0];
    $after_id{$id} = register_timedhandler(Interval => $T,
                          Repeat => 0,
                          Call => sub {
				ui_output("($F[0] of time have passed, running '$F[1]'.)");
				dispatch_event({Type => 'userinput',
					Text => $F[1]});
				delete $after{$id};
			});
    ui_output("(After $F[0] of time, I will run '$F[1]'.) (id $id)");
    $id++;
    return 0;
}

1;
