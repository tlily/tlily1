# $Header: /data/cvs/tlily/extensions/keepalive.pl,v 1.3 1998/06/07 09:55:48 danaf Exp $
#
# keepalive -- periodically ping the server, just to verify our connection
#              is still there.
#

my $pinging = 0;

sub keepalive($) {
    my($handler) = @_;

ui_output("(keepalive)");
    if ($pinging == 1) {
	ui_output("(server has not yet responded to last ping)");
	$pinging = 2;
    } elsif ($pinging == 0) {
	cmd_process("/ping", sub {
			my($event) = @_;
			next unless ($event->{Text} =~ m|/ping|);
			if ($pinging == 2) {
			    ui_output("(server is responding again)");
			}
			$pinging = 0;
		    });
    }
    
    return 0;
}


if ($config{keepalive_interval} <= 0) {
    $config{keepalive_interval} = 600;
}

register_timedhandler(Interval => $config{keepalive_interval},
		      Repeat => 1,
		      Call => \&keepalive);
