# $Header: /data/cvs/tlily/extensions/keepalive.pl,v 2.2 1998/12/29 06:53:58 neild Exp $
#
# keepalive -- periodically ping the server, just to verify our connection
#              is still there.
#

register_help_short("keepalive", "Send periodic pings to the server.");
register_help_long("keepalive",
'The keepalive extension is useful for maintaining a connection to the
server on links which drop after a period of inactivity.  (Such as when
sitting behind a firewall doing NAT.)  Keepalive will send a "/why" to
the server every few minutes.  There are two configuration variables:

    $keepalive_interval - Specifies the frequency (in seconds) to send pings.
    $keepalive_debug    - Set this to be notified when a ping is sent.');

my $pinging = 0;

sub keepalive($) {
    my($handler) = @_;

    ui_output("(keepalive)") if ($config{keepalive_debug});
    if ($pinging == 1) {
	ui_output("(server not responding)");
	$pinging = 2;
    } elsif ($pinging == 0) {
	$pinging = 1;
	cmd_process("/why", sub {
			my($event) = @_;
			$event->{ToUser} = 0;
			return unless ($event->{Type} eq 'endcmd');
			if ($pinging == 2) {
			    ui_output("(server is responding again)");
			}
			$pinging = 0;
			return;
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
