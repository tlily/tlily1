# $Header: /data/cvs/tlily/extensions/autojoin.pl,v 1.2 1998/05/29 05:12:24 mjr Exp $
register_eventhandler(Type => 'disccreate',
    Call => sub {
	my($e, $h) = @_;
	if(!$e->Tags) {
	    ui_output("(Auto-Joining $e->{Name})");
	    dispatch_event({Type => 'userinput',
			    Text => "/join $e->{Name}"});
	}
	return 0;
    }
);

