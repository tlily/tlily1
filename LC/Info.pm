# -*- Perl -*-
package LC::Info;

use Exporter;
use LC::UI;
use LC::Server;
use LC::parse;
use LC::User;
use LC::Command;
use LC::State;
use LC::log;
use IO::File;

@ISA = qw(Exporter);

@EXPORT = qw(info_init);


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
	log_notice("(info buffer file not found)");
	return;
    }

    my @lines = $fh->getlines();
    $fh->close();
    unlink($tmpfile);

    my $size=@lines;

    my $eh;
    $eh = register_eventhandler('export', sub {
	my($event) = @_;
	if ($event->{Response} eq 'OKAY') {
	    my $l;
	    foreach $l (@lines) {
		server_send($l);
	    }
	}
	deregister_eventhandler('export', $eh);
    });
    
    server_send("\#\$\# export_file info $size $disc\n");
}


sub info_edit($) {
    my($target) = @_;

    my $itarget = $target || user_name();

    my @lines = ();
    cmd_process("/info $itarget", sub {
	my($event) = @_;
	$event->{Invisible} = 1;
	if ($event->{Line} =~ /^\* (.*)/) {
	    return if ((@lines == 0) &&
		       ($event->{Line} =~ /^\* Last Update: /));
	    push @lines, substr($event->{Line},2);
	} elsif ($event->{Type} eq 'endcmd') {
	    info_set($target, @lines);
	}
    });
}


sub info_init() {
    register_user_input_handler(sub {
	my($event) = @_;
	if ($event->{Line} =~ m|^\s*/info\s+set\s*(.*?)\s*$|) {
	    info_set($1);
	    $event->{Server} = 0;
	} elsif ($event->{Line} =~ m|^\s*/info\s+edit\s*(.*?)\s*$|) {
	    info_edit($1);
	    $event->{Server} = 0;
	}
	return 0;
    });
}


1;
