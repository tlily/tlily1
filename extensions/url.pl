#
# URL handling
#

my @urls = ();

sub handler {
    my($event, $handler) = @_;

    $event->{Body} =~ s|(http://\S+)|push @urls, $1; "<url>$1</url>";|ge;
    $event->{Body} =~ s|(ftp://\S+)|push @urls, $1; "<url>$1</url>";|ge;
    return 0;
}

register_eventhandler(Type => 'send', Call => \&handler);
