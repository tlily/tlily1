package LC::IO;

use Exporter;
use Curses;
use IO::Select;
use POSIX;
use LC::UI;

my %status;

@ISA = qw(Exporter);

@EXPORT = qw(&ui_output &ui_status &ui_start &ui_process &ui_attr &ui_end);


sub ui_attr {
    &LC::UI::attr_define(@_);
}

# put out a chunk of output..
sub ui_output {
    my ($out)=@_;

#    &main::log_debug("ui_output \"$out\"");
    if ($out eq "") { LC::UI::addline(""); }
    foreach $line (split /\r?\n/,$out) {
#	&main::log_debug("Output \"$line\"");
	&LC::UI::addline($line);
    }
}


sub ui_status {
    my %s2=@_;

    foreach (keys %s2) {
	if ($s2{$_} eq "incr") {
	    $status{$_}++;
	} elsif ($s2{$_} eq "decr") {
	    $status{$_}--;
	} else {
	    $status{$_}=$s2{$_}; 
	}
    }


    my @left;
    my $name=$status{pseudo};
    $name .= "[$status{blurb}]" if (defined($status{blurb}));
    push @left, $name if length($name);
    push @left," -- $status{page_status} -- " 
                                     if (length($status{page_status}));
    my @right;
    push @right, "$status{here} Here|$status{away} Away|$status{detached} Detach"
                                     if (defined($status{detached}));
    push @right, $status{server}     if (defined($status{server}));
    push @right, $status{status}     if (defined($status{server}));
    
    my $left=join ' | ',@left;
    my $right=join ' | ',@right;
    my $lr=length($right);
    my $ll=80-$lr;    

    # favor things on the right over the left.
    $fmt="%-$ll.$ll" . "s%$lr.$lr" . "s";
    $status_line=sprintf($fmt,$left,$right);

    $status_line =~ s:\|:<whiteblue>\|</whiteblue>:g;
    $status_line =~ s:ONLINE:<greenblue>ONLINE</greenblue>:;

    
    LC::UI::sline_set($status_line);

      
}


sub ui_start {
    LC::UI::init();
}

sub ui_end {
    LC::UI::end();
}

# note: keep calling until it returns undef!
sub ui_process {
    my $foo;
#    main::log_debug("ui_process block");
    $foo=LC::UI::handle_input();
#    main::log_debug("ui_process unblock");
    return $foo;
}

1;








