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

sub cmd {
    ($arg)=@_;
    
    if ($arg eq "clear") {
       ui_output("(cleared URL list)");
       @urls=();
       return;
    }
    
    if (@urls == 0) {
       ui_output("(no URLs captured this session)");
       return;
    }
    ui_output("| URLs captured this session:");
    foreach (@urls) {
       ui_output("| $_");
    }
}

register_eventhandler(Type => 'send', Call => \&handler);
register_user_command_handler('url', \&cmd);
register_help_short('url', "View list of captured urls");
register_help_long('url', "
Usage: %url
       %url clear
");
