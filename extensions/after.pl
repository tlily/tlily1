# $Header: /data/cvs/tlily/extensions/after.pl,v 2.1 1998/06/12 08:56:24 albert Exp $
register_user_command_handler('after', \&after_handler);
register_help_short('after', "Run a lily command after a delay");
register_help_long('after', qq(Usage:
%after (offset) (command)
Runs (command) after (offset) amount of time.

%after
List all pending afters.

%after cancel (id)
Cancel after #(id).

offset can be:
      N        N seconds
      Ns       N seconds
      Nm       N minutes
      Nh       N hours
      Nd       N days
));

my %after;
my %after_id;
my %after_when;
my $id=0;

sub after_handler {
    my($args) = @_;
    my(@F);
    if($args eq '') {
        ui_output(sprintf("(%2s\t%-17s\t%s)", "Id", "When", "Command"));
	my $k;
	foreach $k (keys %after) {
       		($sec,$min,$hour,$mday,$mon,$year) = localtime($after_when{$k});
	    ui_output(sprintf("(%2d\t%02d:%02d:%02d %02d/%02d/%02d\t%s)", $k, $hour,$min,$sec,$mon,$mday,$year, $after{$k}));
	}
	return 0;
    }
	
    if($args =~ /cancel\s+(\d+)\s*$/) {
	my $tbc = $1;
	ui_output("(Cancelling afterid $tbc ($after{$tbc}))");
	deregister_handler($after_id{$tbc});
	delete $after{$tbc}; delete $after_id{$tbc}; delete $after_when{$tbc};
	return 0;
    }

    $args =~ m/^\s*(\d+[hmsd]?)\s+(.*?)\s*$/;
    @F = ($1,$2);

    my $T;
    if($F[0] =~ m/^(\d+)s?$/) {
	$T = $1;
 	$W = time + $1;
    }
    elsif($F[0] =~ m/^(\d+)m$/) {
	$T = $1 * 60;
	$W = time + ($1 * 60);
    }
    elsif($F[0] =~ m/^(\d+)h$/) {
	$T = $1 * 3600;
	$W = time + ($1 * 3600);
    } 
    elsif($F[0] =~ m/^(\d+)d$/) {
	$T = $1 * 86400 ;
	$W = time + ($1 * 86400); 
    } 
    else {
	ui_output("Usage: %after (offset) (command)");
	return 0;
    }

    $after{$id} = $F[1];
    $after_when{$id} = $W;
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

sub unload() {
  foreach $k (keys %after) {
    ui_output("(Cancelling afterid $k ($after{$k}))");
    deregister_handler($after_id{$k});
    delete $after{$k}; delete $after_id{$k}; delete $after_when{$k};
  }
}

1;
