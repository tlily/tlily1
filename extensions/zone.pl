# -*- Perl -*-
#
# Timezone support.
# This module rewrites dates into the local timezone.
#

%time_prefixes = (' -> ' => 1,
		  ' <- ' => 1,
		  ' >> ' => 1,
		  ' << ' => 1,
		  '# -> ' => 1,
		  '# <- ' => 1,
		  '# >> ' => 1,
		  '# << ' => 1,
		  '*** ' => 1,
		  '# *** ' => 1);


sub zonewriter($$) {
    my($event, $handler) = @_;

    if ($event->{Text} =~ /^(.*)\((\d\d):(\d\d)\)(.*)$/) {
	my $prefix = $1;
	my $init = $1;
	my $suffix = $4;
	my $t = ($2 * 60) + $3;
	$init =~ s/^%command \[\d+\] //;
	if ($time_prefixes{$init}) {
	    $t += $config{zonedelta};
	    $t += (60 * 24) if ($t < 0);
	    $event->{Text} = sprintf("%s(%02d:%02d)%s",
				     $prefix, int($t / 60), $t % 60, $suffix);
	}
    }

    return 0;
}

sub whowriter($$) {
    my($event, $handler) = @_;

    my $tstr = substr($event->{Text}, 41, 8);
    #ui_output("tstr = `$tstr'");
    return 0 unless ($tstr =~ /^\s*(\d+):(\d\d):(\d\d)/);

    my $t = ($1 * 60) + $2;
    $t += $config{zonedelta};
    $t += (60 * 24) if ($t < 0);
    $tstr = sprintf("%02d:%02d:%02d", int($t / 60), $t % 60, $3);
    substr($event->{Text}, 41, 8) = $tstr;

    return 0;
}

if ($config{zonedelta}) {
    register_eventhandler(Type => 'serverline',
			  Order => 'before',
			  Call => \&zonewriter);

    register_eventhandler(Type => 'who',
			  Order => 'before',
			  Call => \&whowriter);
}

