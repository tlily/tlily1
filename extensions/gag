# -*- Perl -*-

#
# The gag extension adds the ability to `gag' all sends from a given user.
#

%gagged = ();

# Is there a better way?
sub isupper($) {
    my($c) = @_;
    return ((ord($c) >= 'A') && (ord($c) <= 'Z')) ? 1 : 0;
}

sub muffle($) {
    my($line) = @_;
    my $new = $line;

    $new =~ s/\b\w\b/m/g;
    $new =~ s/\b\w\w\b/mm/g;
    $new =~ s/\b\w\w\w\b/mrm/g;
    $new =~ s/\b(\w+)\w\w\w\b/'m'.('r'x length($1)).'fl'/ge;

    my $i;
    for ($i = 0; $i < length($line); $i++) {
	substr($new, $i, 1) = uc(substr($new, $i, 1))
	    if (isupper(substr($line, $i, 1)));
    }

    return $new;
}

sub gag_event_handler(\%\%) {
    my($event,$handler) = @_;

    $event->{Text} = muffle($event->{Text})
	if ($gagged{$event->{From}});
    return 0;
}

sub gag_command_handler($) {
    my($args) = @_;

    if ($args eq '') {
	if (scalar(keys %gagged) == 0) {
	    ui_output("(no users are being gagged)");
	} else {
	    ui_output("Gagged users: " . join(', ', keys %gagged));
	}
	return;
    }

    $name = expand_name($args);
    if ((!defined $name) || ($name =~ /^-/)) {
	ui_output("(could find no match to \"$args\")");
	return;
    }

    if ($gagged{$name}) {
	delete $gagged{$name};
	ui_output("($name is no longer gagged.)");
    } else {
	$gagged{$name} = 1;
	ui_output("($name is now gagged.)");
    }

    return;
}

register_eventhandler(Type => 'send',
		      Call => \&gag_event_handler);
register_user_command_handler('gag', \&gag_command_handler);
register_help_short('gag', 'affix a gag to a user');
register_help_long('gag',
"The %gag command replaces the text of all sends from a user with an
amusing string of mrfls.
usage: %gag
       %gag [user]");

1;
