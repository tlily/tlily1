# -*- Perl -*-
# $Header: /data/cvs/tlily/extensions/pager.pl,v 2.1 1998/06/12 08:56:43 albert Exp $

#
# The pager extension allows the user the ability to turn on and off paging
#

register_user_command_handler('page', \&page_command_handler);
register_help_short('page', 'set automatic page scrolling');
register_help_long('page',
"The %page command allows the user to specify whether unseen text should 
autonatically scroll out of view, or whether a -- MORE -- prompt will appear
prompting the user.
usage: %page
       %page [on|off]");


sub page_command_handler($) {
    my($args) = @_;

    if ($args eq '') {
	if ($config{pager}) {
		ui_output("(paging is currently turned on)");
	} else {
		ui_output("(paging is currently turned off)");
	}
	return;
    }

    if ($args == 1 || $args eq "on") {
	$config{pager} = 1;
	ui_output("(paging is now turned on)");
    } elsif ($args == 2 || $args eq "off") {
	$config{pager} = 0;
	ui_output("(paging is now turned off)");
    }

    return;
}

1;
