# -*- Perl -*-
# $Header: /data/cvs/tlily/extensions/info.pl,v 1.17 1998/05/31 00:28:37 steve Exp $

sub info_set(%) {
    my %args=@_;
    
    my $disc=$args{disc};
    my $edit=$args{edit};
    my @data=@{$args{data}};

    if ($edit) {
	local(*FH);
        my $tmpfile = "/tmp/tlily.$$";
		  my $mtime = 0;
	
	unlink($tmpfile);
	if (@data) {
	    open(FH, ">$tmpfile") or die "$tmpfile: $!";
	    foreach (@data) { chomp; print FH "$_\n"; }
		 $mtime = (stat FH)[10];
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

	if ((stat FH)[10] == $mtime) {
		ui_output("(info not changed)");
		close FH;
		unlink($tmpfile);
		return;
	}

	@data = <FH>;
	close FH;
	unlink($tmpfile);
    }

    my $size=@data;

    register_eventhandler(Type => 'export',
			  Call => sub {
	my($event,$handler) = @_;
	if ($event->{Response} eq 'OKAY') {
	    my $l;
	    foreach $l (@data) {
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

    ui_output("(getting info for $itarget)");
    my @data = ();
    cmd_process("/info $itarget", sub {
	my($event) = @_;
	$event->{ToUser} = 0;
	if ($event->{Text} =~ /^\* (.*)/) {
	    return if ((@data == 0) &&
		       ($event->{Text} =~ /^\* Last Update: /));
	    push @data, substr($event->{Text},2);
	} elsif ($event->{Type} eq 'endcmd') {
	    map { s/\\(.)/$1/g } @data;
	    info_set(disc=>$target,
		     data=>\@data,
		     edit=>1);
	}
	return 0;
    });
}


sub info_cmd($) {
    my ($cmd,$disc) = split /\s+/,"@_";
    if ($cmd eq 'set') {
		info_set(disc=>$disc,
			 edit=>1);
    } elsif ($cmd eq 'edit') {
		info_edit($disc);
    } else {
		server_send("/info @_\r\n");
    }
}

sub export_cmd($) {
    my ($file, $disc);
    my @args=split /\s+/,"@_";
    if (@args == 1) {
	($file) = @args;
    } else {
	($file,$disc) = @args;
    }
    my $rc=open(FH, "<$file");
    unless ($rc) {
	ui_output("(file \"$file\" not found)");
	return;
    }
    @lines=<FH>;
    close(FH);
    info_set(data=>\@lines,
	     disc=>$disc,
	     edit=>0);
}


register_user_command_handler('info', \&info_cmd);
register_user_command_handler('export', \&export_cmd);

    register_eventhandler(Type => 'scommand',
			  Call => sub {
		my($event,$handler) = @_;
		if (config_ask("info")) {
		    if ($event->{Command} eq 'info') {
			info_cmd(join(' ', @{$event->{Args}}));
			$event->{ToServer} = 0;
		    }
		}
		return 0;
    });

register_help_short("info", "Improved /info functions");
register_help_long("info", "
%info set  [discussion]      - Loads your editor and allows you to set your 
                               /info
%info edit [discussion|user] - Allows you to edit or view (in your editor)
                               your /info, or that of a discussion or user.
			       (a handy way to save out someone's /info to 
			        a file or to edit a /info)
%info clear [discussion]     - Allows you to clear a /info.

Note: You can set your editor via \%set editor, or the VISUAL and EDITOR
      environment variables.

");

register_help_short("info", "Export a file to /info");
register_help_long("export", "
%export <filnename> [discussion] - Allows you to set a /info to the contents of 
                               a file
");


1;
