# -*- Perl -*-
# $Header: /data/cvs/tlily/extensions/startup.pl,v 2.1 1998/06/12 08:56:52 albert Exp $

register_eventhandler(Type => 'connected',
		      Order => 'after',
		      Call => \&startup_handler);

sub startup_handler ($$) {
    my($event,$handler) = @_;
    if(-f $ENV{HOME}."/.lily/tlily/Startup") {
	open(SUP, "<$ENV{HOME}/.lily/tlily/Startup");
	if($!) {
	    ui_output("Error opening Startup: $!");
	    deregister_handler($handler->{Id});
	    return 0;
	}
        ui_output("(Running ~/.lily/tlily/Startup)\n");
	while(<SUP>) {
	    chomp;
	    dispatch_event({Type => 'userinput', Text => $_});
	}
	close(SUP);
    } else {
        ui_output("(No Setup file found.)");
        ui_output("(If you want to install one, call it ~/.lily/tlily/Startup)");
    }
    deregister_handler($handler->{Id});
    return 0;
}

1;
