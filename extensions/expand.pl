# -*- Perl -*-

my %expansions = ('sendgroup' => '',
		  'sender'    => '',
		  'recips'    => '');

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
    } elsif (($key eq ':') || ($key eq ';')) {
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

    return if ($pos == 0);

    my $partial = substr($line, 0, $pos);

    # Only expand if we are in the destination zone.
    return if ($partial =~ /[\@\[\]\;\:\=\"\?\s]/);

    $partial =~ s/^.*,//;
    my $full = expand_name($partial);
    $full =~ tr/ /_/;

    return unless($full);
    substr($line, $pos - length($partial), length($partial)) = $full;
    $pos += length($full) - length($partial);

    return ($line, $pos, 2);
}


ui_callback(':', \&exp_expand);
ui_callback(';', \&exp_expand);
ui_callback('=', \&exp_expand);
ui_callback('C-i', \&exp_complete);

register_eventhandler(Type => 'userinput',
		      Call => sub {
			  my($event,$handler) = @_;
			  if ($event->{Text} =~ /^([^:;\s]*)[;:]/) {
			      exp_set('recips', $1);
			  }
			  return 0;
		      });

register_eventhandler(Type => 'privhdr',
		      Call => sub {
			  my($event,$handler) = @_;
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
