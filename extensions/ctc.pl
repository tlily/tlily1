# -*- Perl -*-
# $Header: /data/cvs/tlily/extensions/ctc.pl,v 2.2 1999/01/14 00:21:43 steve Exp $

# A client to client transfer user interface.  This uses Httpd.pm to serve
# the files.

use Socket;
use Sys::Hostname;

my %pending;
my %received;

# Make sure the daemon's parser is loaded.
BEGIN {
    extension ("httpd");
}

sub ctc_cmd ($) {
    my ($cmd, @rest) = split /\s+/, "@_";

    if ($cmd =~ /^send$/i) {
	my ($to, $file) = @rest;

	# Checking for the existence of the file is done in register_webfile
	# It would be nice to add some smartness here eventually.

	# Generate an alias.
	my $alias;
	my @tmp = split /\//, $file;
	my $shfile = pop @tmp;
	# There's a better way, I'm sure.
	for (my $i = 0; $i < 8; $i++) {
	    my $c = rand (26);
	    my $r = rand (100);
	    $alias .= ($r < 50) ? chr($c + 65) : chr ($c + 97);
	}
	$alias .= "/$shfile";
#	ui_output("(Using alias $alias)");

	if (($rc = register_webfile (File => $file, Alias => $alias)) < 0) {
	    ui_output("(Unable to find file $file)");
	    return;
	}
	$pending{$alias} = { File => $file, To => "\L$to" };

	my $hostaddr = inet_ntoa(inet_aton(hostname()));

	ui_output("(Sending file request to $to)");
	# How do I find out what ip address to use?
	cmd_process("$to;@@@ ctc send @@@ http://$hostaddr:$rc/$alias",
	    sub {
		$_[0]->{ToUser} = 0 unless ($_[0]->{Type} eq 'send');
	    });
	return;
    }

    if ($cmd =~ /^get$/i) {
	my ($from, $file) = @rest;

	if (!$from) {
	    ui_output("(You must specify a user to get from)");
	    return;
	}

	$lfrom = "\L$from";
	if ((!(exists($received{$lfrom}))) ||
	    (!(scalar(@{$received{$lfrom}})))) {
	    ui_output("(No pending sends from $from)");
	    return;
	}

	my $url = 0;

	if ($file) {
	    for (my $i = 0; $i < scalar(@{$received{$lfrom}}); $i++) {
		if ($received{$lfrom}->[$i] =~ /${file}$/) {
		    $url = splice @{$received{$lfrom}}, $i, 1;
		    last;
		}
	    }
	    if (!url) {
		ui_output("($from did not send you a file named $file)");
		return;
	    }
	} else {
	    $url = shift @{$received{$lfrom}};
	}

	ui_output("(ctc get is unimplemented, please retrieve the url $url)");
	return;
    }

    if ($cmd =~ /^list$/i) {
	ui_output(" Type   User                    Filename");

	foreach $p (keys %pending) {
	    ui_output(sprintf(" SEND   %-23s %s", $pending{$p}->{To},
		$pending{$p}->{File}));
	}
	foreach $p (keys %received) {
	    foreach $q (@{$received{$p}}) {
		($r) = ($q =~ m|http://.+/.+/(.+)$|);
		ui_output(sprintf(" GET    %-23s %s", $p, $r));
	    }
	}
    }

    if ($cmd =~ /^cancel$/i) {
	my ($to, $file) = @rest;

	foreach $p (keys %pending) {
	    if (!$to || $pending{$p}->{To} eq "\L$to") {
		deregister_webfile($p);
		delete $pending{$p};
	    }
	}
	my $o = ($to) ? " to $to" : "";
	ui_output("(All pending sends" . $o ." cancelled)");
    }
}
sub file_done ($$) {
    my ($event, $handle) = @_;

    if (exists ($pending{$event->{File}})) {
	ui_output ("(File $pending{$event->{File}}->{File} sent completely)");
	delete $pending{$event->{File}};
	deregister_webfile ($event->{File});
    }
}

sub send_handler ($$) {
    my ($event, $handle) = @_;

    return 0 unless ($event->{Body} =~ s/^@@@ ctc send @@@\s*//);

    $event->{ToUser} = 0;

    my ($file) = ($event->{Body} =~ m|^http://.+/.+/(.+)$|);

    push (@{$received{"\L$event->{From}"}}, $event->{Body});

    ui_output("(Recieved ctc send request file \"$file\" from $event->{From})");
    ui_output("(Use %ctc get $event->{From} to receive)");
    return 1;
}

register_eventhandler( Type => 'httpdfiledone',
		       Call => \&file_done);
register_eventhandler( Type => 'send',
		       Order => 'before',
		       Call => \&send_handler
		     );
register_user_command_handler ('ctc', \&ctc_cmd);

register_help_short ("ctc", "Client to client transfer");
register_help_long  ("ctc", "
%ctc send <user> <file>      - Sends the specified file to the user.
%ctc get  <user> [<file>]    - Gets the (optionally specified) file from
                               the specified file.
%ctc list                    - List pending sends and gets.
");

1;
