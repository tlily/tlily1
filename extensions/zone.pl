# -*- Perl -*-
# $Header: /data/cvs/tlily/extensions/zone.pl,v 2.1 1998/06/12 08:57:02 albert Exp $
#
# Timezone support.
# This module rewrites dates into the local timezone.
#

register_help_short('zone', "timezone conversion extension");
register_help_long('zone', 
"The zone extension can convert timestamps from the server's native time zone to the your local time zone.   To use it, invoke tlily with the \"zonedelta\" option, which is a number of hours to add to the timestamps (it can be negative).");

register_eventhandler(Type => 'serverline',
		      Order => 'before',
		      Call => \&zonewriter);

register_eventhandler(Type => 'who',
		      Order => 'before',
		      Call => \&whowriter);



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

    if ($config{zonedelta} || $config{zonetype}) {
	if ($event->{Text} =~ /^(.*)\((\d\d):(\d\d)\)(.*)$/) {
	    my $prefix = $1;
	    my $init = $1;
	    my $suffix = $4;
	    my $t = ($2 * 60) + $3;
	    $init =~ s/^%command \[\d+\] //;
	    if ($time_prefixes{$init}) {
		my($h,$m);
		my $ampm = '';
		$t += $config{zonedelta};
		$t += (60 * 24) if ($t < 0);
		$t -= (60 * 24) if ($t >= (60 * 24));
		$h = int($t / 60);
		$m = $t % 60;
		if(defined $config{zonetype}) {
		    if($h >= 12 && $config{zonetype} eq '12')  {
			 $ampm = 'p';
			 $h -= 12 if $h > 12;
		    }
		    elsif($h < 12 && $config{zonetype} eq '12') {
			$ampm = 'a';
		    }
		}
		$event->{Text} = sprintf("%s(%02d:%02d%s)%s",
					 $prefix, $h, $m, $ampm, $suffix);
	    }
	}
    }
    return 0;
}

sub whowriter($$) {
    my($event, $handler) = @_;

    if ($config{zonedelta}) {
	my $tstr = substr($event->{Text}, 41, 8);
	#ui_output("tstr = `$tstr'");
	return 0 unless ($tstr =~ /^\s*(\d+):(\d\d):(\d\d)/);

	my $t = ($1 * 60) + $2;
	$t += $config{zonedelta};
	$t += (60 * 24) if ($t < 0);
	$tstr = sprintf("%02d:%02d:%02d", int($t / 60), $t % 60, $3);
	substr($event->{Text}, 41, 8) = $tstr;
    }
    return 0;
}

1;
