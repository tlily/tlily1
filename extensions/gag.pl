# -*- Perl -*-
# $Header: /data/cvs/tlily/extensions/gag.pl,v 2.1 1998/06/12 08:56:32 albert Exp $

#
# The gag extension adds the ability to `gag' all sends from a given user.
#

my %gagged;


sub gag_command_handler($) {
    my($args) = @_;

    if ($args eq '') {
	if (scalar(keys(%gagged)) == 0) {
	    ui_output("(no users are being gagged)");
	} else {
	    ui_output("(Gagged users: " . join(', ', keys(%gagged)). ")" );
	}
	return;
    }

    my $clear = $args =~ s/ clear$//;
    $name = expand_name($args);
    if ((!defined $name) || ($name =~ /^-/)) {
	ui_output("(could find no match to \"$args\")");
	return;
    }

    if ($gagged{$name}) {
	delete $gagged{$name};
	ui_resetfilter('gag') if $clear;
	ui_output("($name is no longer gagged.)");
    } elsif ($clear) {
    	ui_resetfilter('gag');
	ui_output("($name is no longer muffled.)");
    } else {
	$gagged{$name} = 1;
	ui_resetfilter('gag');
	ui_output("($name is now gagged.)");
    }

    return;
}

sub init() {
    register_eventhandler( Type => 'send',
    			   Order => 'before',
			   Call => sub {
	my ($event, $handler) = @_;

	return 0 unless ($gagged{$event->{From}});

	$event->{Body} = "<<gag>>$event->{From}~$event->{Body}<</gag>>";

	return 0;
    });

    ui_filter('gag', sub {
    	my $line = shift;

	my ($from, $text) = $line =~ /(.*)~(.*)/;

	return $text unless ($from && $gagged{$from});

	my $new = $text;

	$new =~ s/\b\w\b/m/g;
	$new =~ s/\b\w\w\b/mm/g;
	$new =~ s/\b\w\w\w\b/mrm/g;
	$new =~ s/\b(\w+)\w\w\w\b/'m'.('r'x length($1)).'fl'/ge;

	return $new;
    });

    register_user_command_handler('gag', \&gag_command_handler);
    register_help_short('gag', 'affix a gag to a user');
    register_help_long('gag',
    "The %gag command replaces the text of all sends from a user with an
    amusing string of mrfls.  If the optional word 'clear' is used, then
    all previous gagged sends will be changed to their cleartext versions.
    usage: %gag
	   %gag [user] [clear]");
} 

init();

1;
