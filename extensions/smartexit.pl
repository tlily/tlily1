#
# Exit iff a /bye or /detach was done.
#

register_eventhandler(Type => 'userinput',
		      Call => \&handler);

sub handler {
	my($e, $h) = @_;
	my $t = $e->{Text};
	$t =~ s/\s.*$//;

	if ((index("/detach", $t) == 0) ||
	    (index("/bye", $t) == 0)) {
		$config{exit_on_disconnect} = 1;
	}

	return 0;
}
