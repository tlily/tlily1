# $Header: /data/cvs/tlily/extensions/autojoin.pl,v 2.1 1998/06/12 08:56:26 albert Exp $
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

