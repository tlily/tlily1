register_eventhandler(Type  => 'connected',
                      Order => 'after',
                      Call  => \&connected_handler);

register_user_command_handler('autoreview', \&review_cmd);
register_help_short('autoreview', '/review detach on multiple discs');
register_help_long('autoreview', <<END );
%autoreview reviews the discussions listed in the \@autoreview configuration
variable.  It removes all lines beginning with *** from the review.  It
does not print timestamp lines unless the review contains actual sends to
the discussion.

When the autoreview extension is autoloaded, an autoreview will be performed
at connect-time.
END

my @to_review;
my $rev_interesting = 0;
my $rev_start;

sub connected_handler {
	my($event, $handler);
	deregister_handler($handler);

	if ($status_SyncState eq 'sync') {
		register_eventhandler(Type  => 'endcmd',
		                      Order => 'after',
		                      Call  => \&connected_handler);
		return 0;
	}

	review_start();
	return 0;
}

sub review_cmd {
	if (@to_review) {
		ui_output("(You are currently autoreviewing)");
	}
	review_start();
	return 0;
}

sub review_start {
	eval { @to_review = @{$config{autoreview}} };
	return unless (@to_review); 
	review();
}

sub review {
	return unless (@to_review);
	my $target = shift @to_review;
	cmd_process("/review " . $target . " detach", \&review_handler);
}

sub review_handler {
	my($event) = @_;
	if ($event->{Type} eq 'begincmd') {
		$rev_interesting = 0;
		$rev_start = undef;
	} elsif ($event->{Type} eq 'endcmd') {
		review();
	} elsif ($event->{Raw} =~ /^\(Beginning review of.*\)/) {
		$rev_start = $event->{Text};
		$event->{ToUser} = 0;
	} elsif ($event->{Raw} =~ /^\(End of review of.*\)/) {
		$event->{ToUser} = 0 unless ($rev_interesting);
	} elsif ($event->{Raw} eq "") {
		$event->{ToUser} = 0 unless ($rev_interesting);
	} elsif ($event->{Raw} =~ /^\(No events to review for .*\)/) {
		$event->{ToUser} = 0;
	} elsif ($event->{Raw} =~ /^# \*\*\*/) {
		$event->{ToUser} = 0;
	} elsif ($event->{Raw} =~ /^# ###/ && !$rev_interesting) {
		$event->{ToUser} = 0;
		$rev_start .= "\n" . $event->{Text};
	} elsif (!$rev_interesting) {
		$rev_interesting = 1;
		ui_output($rev_start) if (defined $rev_start);
	}
	return 0;
}
