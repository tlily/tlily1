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

