# -*- Perl -*-

#
# The gag extension adds the ability to `gag' all sends from a given user.
#


sub gag_command_handler($) {
    my($args) = @_;

    if ($args eq '') {
	if (scalar(ui_gaglist()) == 0) {
	    ui_output("(no users are being gagged)");
	} else {
	    my @users=ui_gaglist(); 
	    ui_output("(Gagged users: " . join(', ', @users). ")" );
	}
	return;
    }

    $name = expand_name($args);
    if ((!defined $name) || ($name =~ /^-/)) {
	ui_output("(could find no match to \"$args\")");
	return;
    }

    if (ui_gagged($name)) {
	ui_ungag($name);
	ui_output("($name is no longer gagged.)");
    } else {
	ui_gag($name);
	ui_output("($name is now gagged.)");
    }

    return;
}

register_user_command_handler('gag', \&gag_command_handler);
register_help_short('gag', 'affix a gag to a user');
register_help_long('gag',
"The %gag command replaces the text of all sends from a user with an
amusing string of mrfls.
usage: %gag
       %gag [user]");

1;
