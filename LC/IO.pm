package LC::IO;

use Exporter;
use Curses;
use IO::Select;
use POSIX;
use LC::UI;

my %status;

@ISA = qw(Exporter);

@EXPORT = qw(&ui_output &ui_status &ui_start &ui_process &ui_end);


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

    foreach (keys %s2) { $status{$_}=$s2{$_}; }
    
    $n="";
    $n=$status{pseudo} if (defined($status{pseudo}));
    $n.=" [$status{blurb}]" if (defined($status{blurb}));

    $s="";
    $s.="|$status{parse_state}|";
    
    my @s;
    push @s, "$status{here} Here" if (defined($status{here}));
    push @s, "$status{away} Away" if (defined($status{away}));
    push @s, "$status{detached} Detach" if (defined($status{detached}));
    $s .= join "|",@s;
    
    my $status_line=sprintf ("%-20.20s %26.26s %23.23s | %6.6s",
			     $n,
			     $s,
			     $status{server},
			     $status{status});

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








