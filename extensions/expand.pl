# -*- Perl -*-

my %expansions = ('sendgroup' => '',
		  'sender'    => '',
		  'recips'    => '');

my @past_sends = ();

my $last_send;

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

register_eventhandler(Type => 'usend',
		      Call => sub {
			  my($event,$handler) = @_;
			  my $dlist = join(',', @{$event->{To}});
			  @past_sends = grep { $_ ne $dlist } @past_sends;
			  unshift @past_sends, $dlist;
			  pop @past_sends if (@past_sends > 5);
			  exp_set('recips', $dlist);
			  $last_send = $event->{Body};
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
	if ($config{emote_oops}) {
		if (!defined $last_send) {
			ui_output("(but you haven't said anything)");
			return;
		}
		my $d;
		foreach $d (split /,/, $past_sends[0]) {
			my $dt;
			$d = expand_name($d);
			next unless (substr($d,0,1) eq '-');
			get_disc_state(Name => $d, Disctype => \$dt) or next;
			if ($dt eq 'emote') {
				server_send($past_sends[0] . ";" .
					    $config{emote_oops} . "\r\n");
				server_send($args . ";" . $last_send . "\r\n");
				return;
			}
			last;
		}
	}
	server_send("/oops ".$args."\r\n");
	return;
}

sub also_cmd ($) {
	my($args) = @_;
	&also_proc($args);
	server_send("/also ".$args."\r\n");
}

sub oops_proc ($) {
	my($recips) = @_;
	return if ($recips eq 'text');
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

    register_eventhandler(Type => 'scommand',
			  Call => sub {
			      my($event,$handler) = @_;
			      if (config_ask("oops")) {
				  return 0 unless ($event->{Command} eq 'oops');
				  oops_proc($event->{Args}->[0]);
			      }
			      return 0;
			  });

    register_eventhandler(Type => 'scommand',
			  Call => sub {
			      my($event,$handler) = @_;
			      if (config_ask("also")) {
				  return 0 unless ($event->{Command} eq 'also');
				  also_proc($event->{Args}->[0]);
			      }
			      return 0;
			  });
register_user_command_handler('oops', \&oops_cmd);
register_user_command_handler('also', \&also_cmd);
register_help_short('oops', "/oops with fixed sendlist");
register_help_long('oops', qq(/oops does not fix your sendlist correctly.  This command will send your /oops to the server, as well as fix your sendlist so ; expands correctly afterwards.  If you have 'oops' in your \@slash configuration option, /oops will do the same as %oops.));
register_help_short('also', "/also with fixed sendlist");
register_help_long('also', qq(/also does not fix your sendlist correctly.  This command will send your /also to the server, as well as fix your sendlist so ; expands correctly afterwards.  If you have 'also' in your \@slash configuration option, /also will do the same as %also.));

1;
