#
# Exit iff a /bye or /detach was done.
#

register_eventhandler(Type => 'scommand',
                      Call => \&handler);

sub handler {
    my($e, $h) = @_;
    my $t = $e->{Text};
    $t =~ s/\s.*$//;

    if (($t =~ m#^/det#) || ($t eq '/bye')) {
	ui_output "Exiting smartly...";
	$config{exit_on_disconnect} = 1;
    }
    return 0;
}
