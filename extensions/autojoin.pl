# $Header: /data/cvs/tlily/extensions/autojoin.pl,v 1.3 1998/06/12 05:38:45 albert Exp $
register_eventhandler(Type => 'disccreate',
    Call => sub {
	my($e, $h) = @_;
	if(!$e->{Tags}) {
	    ui_output("(Auto-Joining $e->{Name})");
	    dispatch_event({Type => 'userinput',
			    Text => "/join $e->{Name}"});
	}
	return 0;
    }
);

