# $Header: /data/cvs/tlily/extensions/terminal.pl,v 1.2 1998/05/29 05:12:34 mjr Exp $
#
# Terminal extension.
#

register_user_command_handler('terminal', \&term_handler);
register_help_short('terminal', "View/change terminal implementation.");
register_help_long('terminal', "Displays (or sets) the terminal implementation to use.  The terminal implementation may also be configured by setting the '\$terminal' configuration file variable.");

sub term_handler {
    my($args) = @_;

    if ($args) {
	$config{'terminal'} = $args;
	ui_end();
	ui_start();
    }

    ui_output("(Terminal is $config{terminal})");
    return 0;
}
