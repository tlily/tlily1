# -*- Perl -*-
package LC::StatusLine;

use Exporter;
use Tie::Hash;
use LC::Server;
use LC::UI;
use LC::parse;
use LC::Config;
use LC::Event;
use LC::log;

@ISA = qw(Exporter Tie::StdHash);

@EXPORT = qw(&statusline_init
	     %status);


%status = (Server => $config{server},
	   Pseudo => '',
	   Blurb => '',
	   State => '');


sub render() {
    my(@left,@right);

    my $name = $status{Pseudo};
    $name .= " [$status{Blurb}]" if (defined($status{Blurb}));
    push @left, $name if (length($name));

    push @right, $status{Server} if (defined($status{Server}));
    push @right, $status{State} if (defined($status{State}));

    my @a = localtime;
    if(defined $config{clockdelta}) {
	my($t) = ($a[2] * 60) + $a[1] + $config{clockdelta};
	$t += (60 * 24) if ($t < 0);
	$a[2] = int($t / 60);
	$a[1] = $t % 60;
    }
    my($ampm);
    if(defined $config{clocktype}) {
	if($a[2] >= 12 && $config{clocktype} eq '12') {
	    $ampm = 'p';
	    $a[2] -= 12 if $a[2] > 12;
	}
	elsif($a[2] < 12 && $config{clocktype} eq '12') {
	    $ampm = 'a';
	}
    }
    push @right, sprintf("%02d:%02d%s", $a[2], $a[1], $ampm);

    my $left=join ' | ',@left;
    my $right=join ' | ',@right;
    my $ll=length($left);
    my $lr=$ui_cols-$ll;    

    # favor things on the left over the right.
    my $fmt="%-$ll.$ll" . "s%$lr.$lr" . "s";
    my $status_line=sprintf($fmt,$left,$right);

    $status_line =~ s:\|:<whiteblue>\|</whiteblue>:g;

    # -- MORE -- prompt
    if (length($status{page_status})) {
	$status_line="                                 -- $status{page_status} -- ";
    }
    
    ui_status($status_line);

    return 0;
}


sub STORE($$$) {
    my($this,$key,$value) = @_;
    return if ($this->{$key} eq $value);
    $this->{$key} = $value;
    render;
}


sub statusline_init() {
    tie %status, 'LC::StatusLine';

    register_eventhandler(Type => 'serverline',
			  Order => 'before',
			  Call => sub {
	my($event, $handler) = @_;
	if ($event->{Text} =~ /^Welcome to \w* at\s+(.*?)\s*$/) {
	    $status{Server} = $1;
	    deregister_handler($handler->{Id});
	}
	return 0;
    });

    register_eventhandler(Type => 'who',
			  Order => 'after',
			  Call => sub {
	my($event, $handler) = @_;
	if ($event->{IsUser}) {
	    $status{Pseudo} = $event->{User};
	    $status{State} = $event->{State};
	}
	return 0;
    });

    register_eventhandler(Type => 'rename',
			  Order => 'after',
			  Call => sub {
	my($event, $handler) = @_;
	$status{Pseudo} = $event->{To} if ($event->{IsUser});
	return 0;
    });

    register_eventhandler(Type => 'blurb',
			  Order => 'after',
			  Call => sub {
	my($event, $handler) = @_;
	$status{Blurb} = $event->{Blurb} if ($event->{IsUser});
	return 0;
    });

    register_eventhandler(Type => 'userstate',
			  Order => 'after',
			  Call => sub {
	my($event, $handler) = @_;
	$status{State} = $event->{To} if ($event->{IsUser});
	return 0;
    });

    register_eventhandler(Type => 'who',
			  Order => 'after',
			  Call => sub {
	my($event, $handler) = @_;
	$status{Pseudo} = $event->{User} if ($event->{IsUser});
	$status{Blurb} = $event->{Blurb} if ($event->{IsUser});
	return 0;
    });

    register_timedhandler(Interval => 15,
			  Repeat => 1,
			  Call => \&render);

    render();
}


1;
