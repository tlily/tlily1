# %eval handler
sub eval_handler($) {
    my($args) = @_;
    eval($args);
    ui_output("* Error: $@") if $@;
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

register_eventhandler(Type => 'userinput',
		      Call => \&bang_handler);
