# -*- Perl -*-

my %expansions = ('sendgroup' => '',
		  'sender'    => '',
		  'recips'    => '');

my @past_sends = ();


sub exp_set($$) {
    my($a,$b) = @_;
    $expansions{$a} = $b;
}


sub exp_expand($$$) {
    my($key, $line, $pos) = @_;

    if ($pos == 0) {
	my $exp;
	if ($key eq '=') {
	    $exp = $expansions{'sendgroup'};
	    return unless ($exp);
	    $key = ';';
	} elsif ($key eq ':') {
	    $exp = $expansions{'sender'};
	} elsif ($key eq ';') {
	    $exp = $expansions{'recips'};
	} else {
	    return;
	}

	$exp =~ tr/ /_/;
	return ($exp . $key . $line, length($exp) + 1, 2);
    } elsif (($key eq ':') || ($key eq ';') || ($key eq ',')) {
	my $fore = substr($line, 0, $pos);
	my $aft  = substr($line, $pos);

	return if ($fore =~ /[:;]/);

	my @dests = split(/,/, $fore);
	foreach (@dests) {
	    my $full = expand_name($_);
	    next unless ($full);
	    $_ = $full;
	    $_ =~ tr/ /_/;
	}

	$fore = join(',', @dests);
	return ($fore . $key . $aft, length($fore) + 1, 2);
    }

    return;
}


sub exp_complete($$$) {
    my($key, $line, $pos) = @_;

    my $partial = substr($line, 0, $pos);
    my $full;

    if (length($partial) == 0) {
	$full = $past_sends[0] . ';';
    } elsif ($partial !~ /[\@\[\]\;\:\=\"\?\s]/) {
	$partial =~ m/^(.*,)?(.*)/;
	$full = $1 . expand_name($2);
	$full =~ tr/ /_/;
    } elsif (substr($partial, 0, -1) !~ /[\@\[\]\;\:\=\"\?\s]/) {
	chop $partial;
	$full = $past_sends[0];
	for (my $i = 0; $i < @past_sends; $i++) {
	    if ($past_sends[$i] eq $partial) {
		$full = $past_sends[($i+1)%@past_sends];
		last;
	    }
	}
	$full .= ';';
    }

    return unless($full);
    substr($line, 0, $pos) = $full;
    $pos += length($full) - length($partial);
    
    return ($line, $pos, 2);
}


ui_callback(',', \&exp_expand);
ui_callback(':', \&exp_expand);
ui_callback(';', \&exp_expand);
ui_callback('=', \&exp_expand);
ui_callback('C-i', \&exp_complete);

register_eventhandler(Type => 'userinput',
		      Call => sub {
			  my($event,$handler) = @_;
			  if ($event->{Text} =~ /^([^:;\s]*)[;:]/) {
			      @past_sends = grep { $_ ne $1 } @past_sends;
			      unshift @past_sends, $1;
			      pop @past_sends if (@past_sends > 5);
			      exp_set('recips', $1);
			  }
			  return 0;
		      });

register_eventhandler(Type => 'send',
		      Call => sub {
			  my($event,$handler) = @_;
			  return 0 unless ($event->{First});
			  return 0 unless ($event->{Form} eq 'private');
			  exp_set('sender', $event->{From});
			  my $me = user_name();
			  my @group = @{$event->{To}};
			  if (@group > 1) {
			      push @group, $event->{From};
			      @group = grep { $_ ne $me } @group;
			      exp_set('sendgroup', join(',',@group));
			  }
			  return 0;
		      });

sub oops_cmd ($) {
	my($args) = @_;
	&oops_proc($args);
	server_send("/oops ".$args."\r\n");
}

sub also_cmd ($) {
	my($args) = @_;
	&also_proc($args);
	server_send("/also ".$args."\r\n");
}

sub oops_proc ($) {
	my($recips) = @_;
	my(@dests) = split(/,/, $recips);
	foreach (@dests) {
	    my $full = expand_name($_);
	    next unless ($full);
	    $_ = $full;
	    $_ =~ tr/ /_/;
	}
	exp_set('recips', join(",", @dests));
}

sub also_proc ($) {
	my($recips) = @_;
	my(@dests) = split(/,/, $recips);
	foreach (@dests) {
	    my $full = expand_name($_);
	    next unless ($full);
	    $_ = $full;
	    $_ =~ tr/ /_/;
	}
	exp_set('recips', join(",", $expansions{'recips'}, @dests));
}

if (config_ask("oops")) {
	register_eventhandler(Type => 'userinput',
		Call => sub {
			my($event,$handler) = @_;
			if($event->{Text} =~ m|^\s*/oops\s*(.*?)\s*$|io) {
				oops_proc($1);
			}
			return 0;
		}
	);
}

if (config_ask("also")) {
	register_eventhandler(Type => 'userinput',
		Call => sub {
			my($event,$handler) = @_;
			if($event->{Text} =~ m|^\s*/also\s*(.*?)\s*$|io) {
				also_proc($1);
			}
			return 0;
		}
	);
}
register_user_command_handler('oops', \&oops_cmd);
register_user_command_handler('also', \&also_cmd);

1;
