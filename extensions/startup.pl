# -*- Perl -*-

sub startup_handler ($$) {
    my($event,$handler) = @_;
    if(-f $HOME."/.lily/tlily/Startup") {
        ui_output("(Sourcing ~/.lily/tlily/Startup)\n");
	do $HOME."/.lily/tlily/Startup";
	ui_output("*** Error: ".$@) if $@;
    } else {
        log_notice("(You may add perl code in ~/.lily/tlily/Startup)");
    }
    deregister_handler($handler->{Id});
    return 0;
}

if($config{startup}) {
    register_eventhandler(Type => 'connected',
			  Order => 'after',
			  Call => \&startup_handler
			  );
}

1;
