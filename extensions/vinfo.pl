#
# insecure.pl
#

register_eventhandler(Type => 'send',
		      Order => 'before',
		      Call => \&send_handler);

register_user_command_handler('vinfo', \&vinfo_handler);
register_help_short('vinfo', "Automatic version information transmission.");

sub command {
    # The bit about 'send' events below is a hack for occasions when you
    # send a vinfo request to yourself.
    cmd_process(join('', @_), sub {
		    $_[0]->{ToUser} = 0 unless ($_[0]->{Type} eq 'send');
		});
}

sub send_version_info {
    my($to) = @_;
    command($to, ";[auto] tlily version is ", $TL_VERSION,
	    ", perl version is ", $],
	    ", terminal is ", $config{'terminal'}, ".");
}

sub send_handler {
    my($event, $handler) = @_;
    return 0 unless ($event->{Body} eq "+++ tlily info +++");

    $event->{ToUser} = 0;

    if ($config{'send_info_ok'}) {
	ui_output("(Sending tlily/perl version info to " . $event->{From} .
		  ")");
	send_version_info($event->{From});
    } else {
	ui_output("(Denying version info request from " . $event->{From} .
		  ".  See %help vinfo for details.  Use %vinfo send to explicitly send a response.)");
#	command("$event->{From};[auto] I'd rather not tell you that.");
    }

    return 0;
}

sub vinfo_handler {
    my @args = split /\s+/, $_[0];
    my $cmd = shift @args || '';

    if ($cmd eq 'request') {
	foreach (@args) {
	    ui_output("(sending version info request to $_)");
	    command("$_;+++ tlily info +++");
	}
    } elsif ($cmd eq 'send') {
	foreach (@args) {
	    send_version_info($_);
	}
    } elsif ($cmd eq 'permit') {
	my $opt = shift @args || 'on';
	if ($opt eq 'on') {
	    ui_output("(Permitting version info requests)");
	    $config{'send_info_ok'} = 1;
	} else {
	    ui_output("(Forbidding version info requests)");
	    $config{'send_info_ok'} = 0;
	}
    } else {
	ui_output("? Usage: vinfo request <user> ...");
	ui_output("?        vinfo send <destination> ...");
	ui_output("?        vinfo permit [on | off]");
    }

    return 0;
}
