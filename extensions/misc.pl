register_eventhandler(Type => 'userinput',
		      Call => \&bang_handler);
register_help_short('eval', "run perl code");
register_help_long('eval', "usage: eval <perl code>");
register_help_short('!', "run shell command");
register_help_long('!', "usage: ! <command>");


# %eval handler
sub eval_handler($) {
    my($args) = @_;
    my $rc = eval($args);
    ui_output("* Error: $@") if $@;
    ui_output("-> $rc") if (defined $rc);
}
register_user_command_handler('eval', \&eval_handler);


# !command handler
sub bang_handler($$) {
    my($event,$handler) = @_;
    if ($event->{Text} =~ /^\!(.*)/) {
	$event->{ToServer} = 0;
	user_showline($event->{Text});
	ui_output(`$1`);
	return 1;
    }
    return 0;
}


