# $Header: /data/cvs/tlily/extensions/pipes.pl,v 2.2 1998/08/17 18:32:42 neild Exp $
#
# Piped command processing.
#

register_eventhandler(Type => 'uunknown',
		      Call => \&pipe_handler);

register_help_short("&", "Pipe lily commands through shell commands");
register_help_long("&", <<END
Usage: &/who | grep foo
       &/review detach > output

A piped command is begin with a "&".  The first component should be a lily command.  The command output may be filtered through shell commands, separated by pipes.  The final output may be redirected through a file with "> file".  If the output is not sent to a file, it is printed to the screen upon command termination.
END
		   );

my $counter = 0;
sub pipe_handler {
    my($event, $handler) = @_;

    return 0 unless ($event->{Text} =~ /^\s*&\s*(.*)/);
    my $cmd = $1;
    $cmd =~ s/\s*$//;

    my $lcmd;
    my $run = '';
    my $mode = 0;
    while ($cmd) {
	if ($cmd =~ /^\|\s*(.*)/) {
	    break if ($mode != 2);
	    $cmd = $1;
	    $run .= "| ";
	    $mode = 1;
	} elsif ($cmd =~ /^>\s*(\S+)\s*(.*)/) {
	    break if ($mode != 2);
	    $cmd = $2;
	    $run .= "> $1 ";
	    $mode = 3;
	} elsif ($cmd =~ /^([^|>]*)(.*)/) {
	    if ($mode == 0) {
		$cmd = $2;
		$lcmd = $1;
		$mode = 2;
	    } elsif ($mode == 1) {
		$cmd = $2;
		$run .= "$1 ";
		$mode = 2;
	    } else {
		break;
	    }
	} else {
	    break;
	}
    }

    if ($cmd || $mode == 1) {
	ui_output("(parse error)");
	return 1;
    }

    my $tmpfile = "/tmp/tlily-out-" . $counter++ . "-" . $$;

    if ($mode != 3) {
	$run .= "> $tmpfile";
	local(*FD);
	sysopen(FD, $tmpfile, O_RDWR|O_CREAT, 0600);
	close(FD);
    }

    my $fd = "pipes--fd--" . $counter;
    my $rc = open($fd, $run);
    if ($rc == 0) {
	my $l = $@; $l =~ s/(\\<)/\\$1/g;
	ui_output("Error in pipe: $l");
    }

    cmd_process($lcmd, sub {
	my($event) = @_;
	$event->{ToUser} = 0;
	if ($event->{Type} eq 'begincmd') {
	} elsif ($event->{Type} eq 'endcmd') {
	    close $fd;
	    if ($mode != $3) {
		local(*FD);
		open(FD, "<$tmpfile");
		my @l = <FD>;
		foreach (@l) {
		    chomp;
		    s/(\\<)/\\$1/g;
		    ui_output($_);
		}
		close(FD);
		unlink($tmpfile);
	    }
	} else {
	    if ($fd) {
		my $rc = print $fd $event->{Raw}, "\n";
		unless ($rc) {
			close $fd;
			undef $fd;
		}
	    }
	}
    });

    return 1;
}
