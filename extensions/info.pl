# -*- Perl -*-

sub info_set($;\@) {
    my($disc,$lref) = @_;

    local(*FH);
    
    my $tmpfile = "/tmp/tlily.$$";

    unlink($tmpfile);
    if ($lref) {
	open(FH, ">$tmpfile") or die "$tmpfile: $!";
	foreach (@$lref) { chomp; print FH "$_\n"; }
	close FH;
    }

    ui_end();
    system("$config{editor} $tmpfile");
    ui_start();

    my $rc = open(FH, "<$tmpfile");
    unless ($rc) {
	ui_output("(info buffer file not found)");
	return;
    }

    my @lines = <FH>;
    close FH;
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
	deregister_handler($handler->{Id});
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
	    map { s/\\(.)/$1/g } @lines;
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

if (config_ask("info")) {
    register_eventhandler(Type => 'scommand',
			  Call => sub {
		my($event,$handler) = @_;
		if ($event->{Command} eq '/info') {
			info_cmd(join(' ', @{$event->{Args}}));
			$event->{ToServer} = 0;
		}
		return 0;
    });
}


register_help_short("info", "Improved /info functions");
register_help_long("info", "
%info set  [discussion]      - Loads your editor and allows you to set your 
                               /info
%info edit [discussion|user] - Allows you to edit or view (in your editor)
                               your /info, or that of a discussion or user.
			       (a handy way to save out someone's /info to 
			        a file or to edit a /info)
%info clear [discussion]     - Allows you to clear a /info.

Note: You can set your editor via \$config{editor}, or the VISUAL and EDITOR
      environment variables.

");


1;
