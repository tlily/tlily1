# -*- Perl -*-
# $Header: /data/cvs/tlily/extensions/source.pl,v 1.1 1998/06/05 23:07:51 steve Exp $

sub do_source($) {
    my ($fname) = @_;
    my $i;
    local(*FH);

    return if $fname eq "";

    my $rc = open (FH, "<$fname");
    unless ($rc) {
	ui_output("($fname not found)");
	return;
    }

    ui_output("(sourcing $fname)");

    my @data = <FH>;
    my $size = @data;
    ui_output("$size lines");
    close FH;

    foreach $l (@data) {
	chomp $l;
# Which one?
#	server_send($l);
	dispatch_event({Type => 'userinput',
			Text => $l});
    }
    return;
}   

sub init() {
    register_user_command_handler('source', \&do_source);
    register_help_short("source", "Evaluate a file as if entered by the user");
    register_help_long("source", "
%source [file] - Play the file to the client as if it was typed by the user.

");
}

init();

1;
