register_eventhandler(Type => 'userinput',
		      Call => \&bang_handler);
register_help_short('eval', "run perl code");
register_help_long('eval', "usage: eval <perl code>");
register_help_short('!', "run shell command");
register_help_long('!', "usage: ! <command>");

register_user_command_handler('version', \&version_handler);
register_help_short('version', "Display the version of Tigerlily and the server");
register_help_long('version', "usage: %version\n* Displays the version of Tigerlily and the server.\n");


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
	$event->{ToServer} = 0;
	ui_output("[beginning of command output]");
	open(FD, "$1 |");
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
sub version_handler($$) {
    my($event,$handler) = @_;
    ui_output("(Tigerlily version $TL_VERSION)\n");
    server_send("/display version\r\n");
    return 0;
}
