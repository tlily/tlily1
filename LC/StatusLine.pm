# -*- Perl -*-
package LC::StatusLine;

use Exporter;
use Tie::Hash;
use LC::Server;
use LC::UI;
use LC::parse;
use LC::config;
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

    register_preparser(sub {
	my($line, $id) = @_;
	if ($line =~ /^Welcome to \w* at\s+(.*?)\s*$/) {
	    $status{Server} = $1;
	    deregister_preparser($id);
	}
    });

    register_eventhandler('who', sub {
	my($event, $id) = @_;
	if ($event->{IsUser}) {
	    $status{Pseudo} = $event->{User};
	    $status{State} = $event->{State};
	}
    });

    register_eventhandler('rename', sub {
	my($event, $id) = @_;
	$status{Pseudo} = $event->{To} if ($event->{IsUser});
    });

    register_eventhandler('blurb', sub {
	my($event, $id) = @_;
	$status{Blurb} = $event->{Blurb} if ($event->{IsUser});
    });

    register_eventhandler('userstate', sub {
	my($event, $id) = @_;
	$status{State} = $event->{To} if ($event->{IsUser});
    });

    render();
}


1;
