# $Header: /data/cvs/tlily/extensions/misc.pl,v 1.16 1998/05/29 05:12:30 mjr Exp $
register_eventhandler(Type => 'uunknown',
		      Call => \&bang_handler);
register_help_short('eval', "run perl code");
register_help_long('eval', "usage: eval <perl code>");
register_help_short('!', "run shell command");
register_help_long('!', "usage: ! <command>");

register_user_command_handler('version', \&version_handler);
register_help_short('version', "Display the version of Tigerlily and the server");
register_help_long('version', "usage: %version\n* Displays the version of Tigerlily and the server.\n");


register_user_command_handler('echo', \&echo_handler);
register_help_short('echo', "Echo text to the screen.");

my $last_command = '';


# %eval handler
sub eval_handler($) {
    my($args) = @_;
    my $rc = eval($args);
    ui_output("* Error: $@") if ($@);
    ui_output("-> $rc") if (defined $rc);
}
register_user_command_handler('eval', \&eval_handler);

# !command handler
sub bang_handler($$) {
    my($event,$handler) = @_;
    if ($event->{Text} =~ /^\!(.*?)\s*$/) {
    	my $cmd = $1;
	$event->{ToServer} = 0;
	$cmd = $last_command if ($cmd =~ /\!/);
	$last_command = $cmd;
	ui_output("[beginning of command output]");
	open(FD, "$cmd 2>&1 |");
	my @r = <FD>;
	close(FD);
	foreach (@r) {
	    chomp;
	    s/([\\<])/\\$1/g;
	    ui_output($_);
	}
	ui_output("[end of command output]");
	return 1;
    }
    return 0;
}

# %version handler
sub version_handler {
    ui_output("(Tigerlily version $TL_VERSION)");
    server_send("/display version\r\n");
    return 0;
}

# %echo handler
sub echo_handler {
    ui_output(join(' ', @_));
    return 0;
}
