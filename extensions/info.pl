# -*- Perl -*-

sub info_set($;\@) {
    my($disc,$lref) = @_;
    
    my $tmpfile = "/tmp/tlily.$$";
    my $EDITOR = $ENV{VISUAL} || $ENV{EDITOR} || "vi";

    unlink($tmpfile);
    if ($lref) {
	my $fh = IO::File->new(">$tmpfile");
	foreach (@$lref) { chomp; $fh->print("$_\n"); }
	$fh->close();
    }

    ui_end();
    system("$EDITOR $tmpfile");
    ui_start();

    my $fh = IO::File->new("<$tmpfile");
    unless ($fh) {
	ui_output("(info buffer file not found)");
	return;
    }

    my @lines = $fh->getlines();
    $fh->close();
    unlink($tmpfile);

    my $size=@lines;

    register_eventhandler(Type => 'export',
			  Call => sub {
	my($event,$handler) = @_;
	if ($event->{Response} eq 'OKAY') {
	    my $l;
	    foreach $l (@lines) {
		server_send($l);
	    }
	}
	deregister_eventhandler($handler->{Id});
	return 0;
    });
    
    server_send("\#\$\# export_file info $size $disc\n");
}


sub info_edit($) {
    my($target) = @_;

    my $itarget = $target || user_name();

    my @lines = ();
    cmd_process("/info $itarget", sub {
	my($event) = @_;
	$event->{ToUser} = 0;
	if ($event->{Text} =~ /^\* (.*)/) {
	    return if ((@lines == 0) &&
		       ($event->{Text} =~ /^\* Last Update: /));
	    push @lines, substr($event->{Text},2);
	} elsif ($event->{Type} eq 'endcmd') {
	    info_set($target, @lines);
	}
	return 0;
    });
}


sub info_cmd($) {
    my ($args) = @_;
    my @argv = split /\s+/, $args;
    my $cmd = shift @argv;

    if ($cmd eq 'set') {
	info_set(shift @argv);
    } elsif ($cmd eq 'edit') {
	info_edit(shift @argv);
    } else {
	server_send("/info $args\r\n");
    }
}


register_user_command_handler('info', \&info_cmd);

if ($config{replace_info}) {
    register_eventhandler(Type => 'userinput',
			  Call => sub {
	my($event,$handler) = @_;
	if ($event->{Text} =~ m|^\s*/info\s*(.*?)\s*$|) {
	    info_cmd($1);
	    $event->{ToServer} = 0;
	}
    });
}


1;
