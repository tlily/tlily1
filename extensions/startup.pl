# -*- Perl -*-

register_eventhandler(Type => 'connected',
		      Order => 'after',
		      Call => \&startup_handler);

sub startup_handler ($$) {
    my($event,$handler) = @_;
    if(-f $ENV{HOME}."/.lily/tlily/Startup") {
        ui_output("(Eval-ing ~/.lily/tlily/Startup)\n");
	do $ENV{HOME}."/.lily/tlily/Startup";
	ui_output("*** Error: ".$@) if $@;
    } else {
        ui_output("(You may add perl code in ~/.lily/tlily/Startup)");
    }
    deregister_handler($handler->{Id});
    return 0;
}

1;
