# -*- Perl -*-
# $Header: /data/cvs/tlily/LC/StatusLine.pm,v 2.2 1998/10/25 18:50:32 mjr Exp $
package LC::StatusLine;

=head1 NAME
 
LC::StatusLine - the status line
 
=head1 SYNOPSIS
 
    (as used from an extension:)

    $mystatus='initial';

    register_statusline(Var => \$mystatus,
			Position => "PACKLEFT");
    # Position may be either "FORCELEFT", "PACKLEFT" or "PACKRIGHT" at present.

    sub setit {
	($mystatus)=@_; 
	redraw_statusline();
    } 
    register_user_command_handler('statusline', \&setit);

    note: redraw_statusline(1) will override the default behavior of deferring the update if it was updated within the last second.
=head1 DESCRIPTION
    
=cut 


use Exporter;
use Tie::Hash;
use LC::Server;
use LC::UI;
use LC::Config;
use LC::Event;

@ISA = qw(Exporter);

@EXPORT = qw(&statusline_init
	     %status
	     &register_statusline
	     &deregister_statusline
	     &redraw_statusline
	     $status_SyncState
	     );

my $current_id=42;
my $lastredraw;

sub redraw_statusline {
    my ($now)=@_;
    my(@left,@right);

    if ($now && !ref($now)) {
	# force update
    } else {
	# limit updates to 1 per second.
	# Also, if the time was change back a signifcant amount, redraw
	return if (abs(time()-$lastredraw) < 1);
	$lastredraw=time();
    }

#    ($package,$filename,$line)=caller();
#    ui_output("* REDRAW called from $package ($filename:$line) *");

    foreach $id (keys %data) {
	if (ref($data{$id})) {
	    $d=$data{$id};
	    my $val=${$d->{Var}};
   	    if (! $val && $d->{Call}) {		
		$val=&{$d->{Call}};
            }
#	    print STDERR "StatusLine Draw ID $id=\"$val\" VAR=$d->{Var} CALL=$d->{Call}\n";
            next unless length($val);
	    
   	    my $position=$d->{Position};
	    if ($position eq "FORCELEFT") {
		unshift(@left,$val);
	    } elsif ($position eq "PACKLEFT") {
		push (@left,$val);
    	    } elsif ($position eq "PACKRIGHT") {		
		push (@right,$val);		
	    } else {		
		ui_output("*WARNING: Unknown StatusLine Position \"$position\"") if ! $warned{$id};
		$warned{$id}=1;
	    }
	}
	
    }

    my $left=join ' | ',@left;
    my $right=join ' | ',reverse @right;
    my $ll=length($left);    
    my $lr=$ui_cols-$ll;


    # favor things on the left over the right.
    my $fmt="%-$ll.$ll" . "s%$lr.$lr" . "s";
    my $status_line=sprintf($fmt,$left,$right);
       
    $status_line = ui_escape($status_line);
    $status_line =~ s:\|:<whiteblue>\|</whiteblue>:g;

    ui_status($status_line);

    return 0;
}



sub statusline_init() {
    $status_Server=$config{server};

    register_statusline(Call => \&status_username,
			Position => "PACKLEFT");

    register_statusline(Call => \&status_time,
			Position => "PACKRIGHT");

    register_statusline(Call => \&status_state,
			Position => "PACKRIGHT");  

    register_statusline(Var => \$status_Server,
			Position => "PACKRIGHT");

    register_eventhandler(Type => 'serverline',
			  Order => 'before',
			  Call => sub {
	my($event, $handler) = @_;
	if ($event->{Text} =~ /^Welcome to \w* at\s+(.*?)\s*$/) {
	    $status_Server = $1;
	    $config{site} = $1;
	    deregister_handler($handler->{Id});
	    redraw_statusline();	    
	}
	return 0;
    });

    register_eventhandler(Type => 'userstate',
			  Order => 'after',
			  Call => sub {
	my($event, $handler) = @_;
	if ($event->{IsUser}) {
	    $status_State = $event->{To};
	    redraw_statusline();       
	}
	return 0;
    });

    register_eventhandler(Type => 'who',
			  Order => 'after',
			  Call => sub {
	my($event, $handler) = @_;
	if ($event->{IsUser}) {
	    $status_Pseudo = $event->{User};
	    $status_State = $event->{State};
	    redraw_statusline();	    
	}
	return 0;
    });

    register_eventhandler(Type => 'rename',
			  Order => 'after',
			  Call => sub {
	my($event, $handler) = @_;
	if ($event->{IsUser}) {
	    $status_Pseudo = $event->{To};
	    redraw_statusline();	
	}
	return 0;
    });

    register_eventhandler(Type => 'blurb',
			  Order => 'after',
			  Call => sub {
	my($event, $handler) = @_;
	if ($event->{IsUser}) {
	    $status_Blurb = $event->{Blurb};
	    redraw_statusline();	
	}
	return 0;
    });

    register_eventhandler(Type => 'who',
			  Order => 'after',
			  Call => sub {
	my($event, $handler) = @_;
	if ($event->{IsUser}) {
	    $status_Pseudo = $event->{User};
	    $status_Blurb = $event->{Blurb};
	    redraw_statusline();
	}
	return 0;
    });

    register_timedhandler(Interval => 15,
			  Repeat => 1,
			  Call => \&redraw_statusline);

    redraw_statusline();
}

sub register_statusline {
    my(%h)=@_;
    $current_id++;
    $data{$current_id}=\%h;
    $h{Id}=$current_id;
    push @{$registered_status_vars{$cmd}},\%h;
    return $h{Id};
}


sub deregister_statusline {
    my($id)=@_;
    delete $data{$current_id};
    return 0;
}

sub status_time {
    my @a = localtime;
    if($config{clockdelta}) {
	my($t) = ($a[2] * 60) + $a[1] + $config{clockdelta};
	$t += (60 * 24) if ($t < 0);
	$t -= (60 * 24) if ($t >= (60 * 24));
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
    sprintf("%02d:%02d%s", $a[2], $a[1], $ampm);
}

sub status_username {
    my $name = $status_Pseudo;
    $name .= " [$status_Blurb]" if (defined($status_Blurb));
    #$name=ui_escape($name);

    return $name;    
}

sub status_state {
    my $ret;
    if ($status_SyncState) {
	$ret=$status_SyncState;
    } else {
	$ret=$status_State if (defined($status_State));
    }
    $ret;
}


1;

