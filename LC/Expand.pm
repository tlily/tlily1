# -*- Perl -*-
package LC::Expand;

use Exporter;

use LC::State;
use LC::User;
use LC::parse;
use LC::UI;

@ISA = qw(Exporter);

@EXPORT = qw(&exp_set &exp_expand &exp_init);

my %expansions = ('sendgroup' => '',
		  'sender'    => '',
		  'recips'    => '');

sub exp_set ($$) {
    my($a,$b) = @_;
    $expansions{$a} = $b;
}


sub exp_expand ($$$) {
    my($key, $line, $pos) = @_;

    if ($pos == 0) {
	my $exp;
	if ($key eq '=') {
	    $exp = $expansions{'sendgroup'};
	    $key = ';';
	} elsif ($key eq ':') {
	    $exp = $expansions{'sender'};
	} elsif ($key eq ';') {
	    $exp = $expansions{'recips'};
	} else {
	    return LC::UI::input_add($key, $line, $pos);
	}
	
	return ($exp . $key . $line, length($exp) + 1, 2);
    } elsif (($key eq ':') || ($key eq ';')) {
	my $fore = substr($line, 0, $pos);
	my $aft  = substr($line, $pos);

	return LC::UI::input_add($key, $line, $pos) if ($fore =~ /[:;]/);

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

    return LC::UI::input_add($key, $line, $pos);
}


sub exp_complete ($$$) {
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


sub exp_init () {
    ui_callback(':' => \&exp_expand);
    ui_callback(';' => \&exp_expand);
    ui_callback('=' => \&exp_expand);
    ui_callback('C-i' => \&exp_complete);

    register_user_input_handler(sub {
	my($event) = @_;
	if ($event->{Line} =~ /^([^:;]*)[;:]/) {
	    exp_set('recips', $1);
	}
	return 0;
    });

    register_eventhandler('privhdr', sub {
	my($event) = @_;
	exp_set('sender', $event->{From});
    });
}
