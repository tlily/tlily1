# -*- Perl -*-
# $Header: /data/cvs/tlily/extensions/ctc.pl,v 2.3 1999/01/28 22:18:22 steve Exp $

# A client to client transfer user interface.  This uses Httpd.pm to serve
# the files.

use Socket;
#use Sys::Hostname;
use Net::Domain qw(hostfqdn);

my %pending;
my %received;

# The ip address to give out.  This need only be determined once.
my $hostaddr;

# Make sure the daemon's parser is loaded.
BEGIN {
    extension ("httpd");
	#    $hostaddr = inet_ntoa(inet_aton(hostname()));
    $hostaddr = inet_ntoa(inet_aton(hostfqdn()));
}

sub ctc_cmd ($) {
    my ($cmd, @rest) = split /\s+/, "@_";
	
    $cmd = "\L$cmd";
	
    if ($cmd eq 'send') {
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
		
		
		ui_output("(Sending file request to $to)");
		cmd_process("$to;@@@ ctc send @@@ http://$hostaddr:$rc/$alias",
					sub {
						$_[0]->{ToUser} = 0 unless ($_[0]->{Type} eq 'send');
					});
		return;
    }
	
    if ($cmd eq 'get') {
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
				if ($received{$lfrom}->[$i]->{URL} =~ /$file$/) {
					$url = splice @{$received{$lfrom}}, $i, 1;
					last;
				}
				if (!url) {
					ui_output("($from did not send you a file named $file)");
					return;
				}
			}
		} else {
			$url = shift @{$received{$lfrom}};
		}
		
		return passive_get($url, $from) if $url->{Passive};
		
		ui_output ("(ctc get is unimplemented)");
		ui_output ("(Please retrieve the url $url->{URL})");
		return;
	}
	
	if ($cmd eq 'list') {
		ui_output(" Type   User                    Filename");
		
		foreach $p (keys %pending) {
			ui_output(sprintf(" SEND   %-23s %s", $pending{$p}->{To},
							  $pending{$p}->{File}));
		}
		foreach $p (keys %received) {
			foreach $q (@{$received{$p}}) {
				($r) = ($q->{URL} =~ m|http://.+/.+/(.+)$|);
				ui_output(sprintf(" GET    %-23s %s", $p, $r));
			}
		}
	}
	
	if ($cmd eq 'cancel') {
		my ($to, $file) = @rest;
		
		foreach $p (keys %pending) {
			if (!$to || $pending{$p}->{To} eq "\L$to") {
				deregister_webfile($p);
				delete $pending{$p};
			}
		}
		my $o = ($to) ? " to $to" : "";
		ui_output("(All pending sends" . $o ." cancelled)");
		return;
	}
	
	if ($cmd eq 'refuse') {
		my ($from, $file) = @rest;
		
		$lfrom = "\L$from";
		if (!$received{$lfrom}) {
			ui_output("(No pending gets from $from)");
			return;
		}
		
		for (my $i = 0; $i < scalar(@{$received{$lfrom}}); $i++) {
			if (!$file || $received{$lfrom}->[$i]->{URL} =~ /$file$/) {
				cmd_process ("$from;@@@ ctc refuse @@@ " .
							 $received{$lfrom}->[$i]->{URL},
							 sub {
								 $_[0]->{ToUser} = 0
								   unless ($_[0]->{Type} eq 'send');
							 } );
				($f) = $received{$lfrom}->[$i]->{URL} =~ m|http://.+/.+/(.+)$|;
				ui_output("(Refusing file $f from $from)");
				splice @{$received{$lfrom}}, $i, 1;
			}
		}
		unless (scalar(@{$received{$lfrom}})) {
			delete $received{$lfrom};
			return;
		}
	}
}
	
sub passive_get ($$) {
	my ($url, $from) = @_;

	($url) = $url =~ m|http://.+/(.+/.+)$|;

	my $port = register_webfile ( File    => $url,
								  Passive => 1,
								);

	cmd_process("$from;@@@ ctc passiveok @@@ http://$hostaddr:$port/$url",
				sub {
					$_[0]->{ToUser} = 0
					  unless ($_[0]->{Type} eq 'send');
				} );
	
#	ui_output("(Passive mode gets have not been implemented yet)");
	return;
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
	
    return 0
	  unless (($event->{Body} =~ s/^@@@ ctc (send|passive|refuse) @@@\s*//));

	my $cmd = $1;
	
    $event->{ToUser} = 0;
	
    my ($alias, $file) = ($event->{Body} =~ m|^http://.+/(.+/(.+))$|);
	
	if (($cmd eq 'send') || ($cmd eq 'passive')) {
		push (@{$received{"\L$event->{From}"}}, 
			  { URL     => $event->{Body},
			    Passive => ($cmd eq 'passive')
			  } );
		
		ui_output
		  ("(Recieved ctc send request file \"$file\" from $event->{From})");
		ui_output("(Use %ctc get $event->{From} to receive)");
		return 1;
	}

	if ($cmd eq 'refuse') {
		if (delete $pending{$alias}) {
			ui_output("($event->{From} refused the file $file)");
		}
		return 1;
	}
}

sub unload () {
    ctc_cmd('cancel');
}

register_eventhandler( Type => 'httpdfiledone',
					   Call => \&file_done
					 );
#register_eventhandler( Type => 'httpdclose',
#				   Call => \&file_done
#			 );
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
%ctc cancel [<user>]         - Cancel pending sends.
%ctc refuse <user> [<file>]  - Refuse a pending get.
");

1;
