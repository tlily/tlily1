# $Header: /data/cvs/tlily/extensions/smartexit.pl,v 2.1 1998/06/12 08:56:49 albert Exp $
#
# Exit if a /bye or /detach was done.
#

register_eventhandler(Type => 'scommand',
                      Call => \&handler);

sub handler {
    my($e, $h) = @_;
    my $t = $e->{Text};
    $t =~ s/\s.*$//;

    if (($t =~ m#^/det#) || ($t eq '/bye')) {
	ui_output "(Exiting smartly)";
	$config{exit_on_disconnect} = 1;
    }
    return 0;
}
