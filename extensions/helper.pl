# -*- Perl -*-
# $Header: /data/cvs/tlily/extensions/helper.pl,v 1.1 1998/06/05 23:07:48 steve Exp $

my $top = "";

sub help_set(%) {
    my %args = @_;
    my $mtime = 0;
    local(*FH);

    return if $args{Index} eq "";

    my($tempfile) = "/tmp/tlily.$$";

    unlink($tempfile);
    if (@{$args{Data}}) {
    	open (FH, ">$tempfile") or die "$tempfile: $!";
	$mtime = (stat FH)[10];
	foreach (@{$args{Data}}) { chomp; print FH "$_\n"; }
	close FH;
    }

    ui_end();
    system("$config{editor} $tempfile");
    ui_start();

    my $rc = open FH, "<$tempfile";
    unless ($rc) {
    	ui_output("(help buffer file not found)");
	return;
    }

    if ((stat FH)[10] == $mtime) {
    	ui_output("(help not changed)");
	close(FH);
	unlink($tempfile);
	return;
    }

    my @data = <FH>;
    close FH;
    unlink $tempfile;

    server_send("$top\r\n");
    foreach $l (@data) {
    	server_send($l);
    }
    server_send(".\r\n");
    
    return;
}

sub help_edit($$) {
    my($index, $topic) = @_;

    ui_output("(getting help text)");

    my @data = ();
    cmd_process("?gethelp $index $topic", sub {
    	my($event) = @_;
	$event->{ToUser} = 0;
	if ($event->{Type} eq 'endcmd') {
	    help_set( Index => $index,
	    	      Data => \@data);
	    return;
	}
	return if $event->{Text} =~ /^\%begin/ || $event->{Text} =~ /^\.$/;
	if ($event->{Text} =~ /^?sethelp/) {
	    $top = $event->{Text};
	    return;
	}
	push @data, $event->{Text};
	return;
    });
}

sub help_cmd($) {
    my($cmd, $index, $topic) = split /\s+/, "@_";

# Only %helper edit right now.
    if($cmd eq 'edit') {
    	help_edit($index, $topic);
    } else {
    	server_send("/help @_\r\n");
    }
    return;
}

sub init() {
    register_user_command_handler('helper', \&help_cmd);
    register_help_short("helper", "Interface to the ?commands");
    register_help_long("helper", "
%helper edit ([index]) [topic] - Loads the help topic into an editor.
%helper                        - Acts as /help.

");
}

init();

1;
