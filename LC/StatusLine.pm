# -*- Perl -*-
package LC::StatusLine;

use Exporter;
use Tie::Hash;
use LC::Server;
use LC::UI;
use LC::parse;
use LC::config;
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
	    deregister_eventhandler($handler->{Id});
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
    });

    register_eventhandler(Type => 'blurb',
			  Order => 'after',
			  Call => sub {
	my($event, $handler) = @_;
	$status{Blurb} = $event->{Blurb} if ($event->{IsUser});
    });

    register_eventhandler(Type => 'userstate',
			  Order => 'after',
			  Call => sub {
	my($event, $handler) = @_;
	$status{State} = $event->{To} if ($event->{IsUser});
    });

    register_eventhandler(Type => 'who',
			  Order => 'after',
			  Call => sub {
	my($event, $handler) = @_;
	$status{Pseudo} = $event->{User} if ($event->{IsUser});
	$status{Blurb} = $event->{Blurb} if ($event->{IsUser});
    });

    render();
}


1;
