# -*- Perl -*-
# $Header: /data/cvs/tlily/extensions/ctc.pl,v 1.1 1999/01/11 21:33:12 steve Exp $

# A client to client transfer user interface.  This uses Httpd.pm to serve
# the files.

my %pending;

# Make sure the daemon's parser is loaded.
BEGIN {
    extension ("httpd");
}

sub ctc_cmd ($) {
    my ($cmd, @rest) = split /\s+/, "@_";

    if ($cmd eq 'send') {
	my ($to, $file) = @rest;

	# Checking for the existence of the file is done in register_webfile
	# It would be nice to add some smartness here eventually.

	# Generate an alias.
	my $alias;
	# There's a better way, I'm sure.
	for (my $i = 0; $i < 8; $i++) {
	    my $c = rand (26);
	    my $r = rand (100);
	    $alias .= ($r < 50) ? chr($c + 65) : chr ($c + 97);
	}
	$alias .= "/$file";
	ui_output("(Using alias $alias)");

	if (($rc = register_webfile (File => $file, Alias => $alias)) < 0) {
	    ui_output("(Unable to find file $file)");
	    return;
	}
	$pending{$alias} = $file;

	ui_output("(Sending file request to $to)");
	cmd_process("$to;@@@ ctc send @@@ http://128.113.175.35:$rc/$alias",
	    sub {
		$_[0]->{ToUser} = 0 unless ($_[0]->{Type} eq 'send');
	    })
    }
}

sub file_done ($$) {
    my ($event, $handle) = @_;

    if (exists ($pending{$event->{File}})) {
	ui_output ("(File $pending{$event->{File}} sent completely)");
	delete $pending{$event->{File}};
	deregister_webfile ($event->{File});
    }
}

register_eventhandler( Type => 'httpdfiledone',
		       Call => \&file_done);
register_user_command_handler ('ctc', \&ctc_cmd);
