# -*- Perl -*-
package LC::Config;

use FileHandle;
use Safe;
use Exporter;
require "dumpvar.pl";

@ISA = qw(Exporter);
@EXPORT = qw(&config_init &config_ask %config);

sub config_init {
    read_init_files();
    parse_command_line();

#    print STDERR "*** load list ***\n";
#    print STDERR join(", ", @{$config{load}}), "\n";
#    print STDERR "*** Done load list ***\n";

    collapse_list($config{load});

#    print STDERR "*** Final load list ***\n";
#    print STDERR join(", ", @{$config{load}}), "\n";
#    print STDERR "*** Done final load list ***\n";

    print STDERR "*** slash list ***\n";
    print STDERR join(", ", @{$config{slash}}), "\n";
    print STDERR "*** Done slash list ***\n";

    collapse_list($config{slash});

    print STDERR "*** Final slash list ***\n";
    print STDERR join(", ", @{$config{slash}}), "\n";
    print STDERR "*** Done final slash list ***\n";
}

sub read_init_files {
    my $ifile;

    foreach $ifile ($main::TL_LIBDIR."/tlily.global",
		    $main::TL_ETCDIR."/tlily.site",
		    $ENV{HOME}."/.lily/tlily/tlily.cf")
    {
	if(-f $ifile) {
	    print STDERR "Loading $ifile\n";

	    my $safe=new Safe;
	    snarf_file($ifile, $safe);

	    local(*stab) = $safe->reval("*::");
	    my $key;
	    print STDERR "*** Examining ", $safe->root, "\n";
	    foreach $key (keys %stab) {
		next if($key =~ /^_/ || $key =~ /::/);
		local(*entry) = $stab{$key};
		if(defined $entry) {
		    $config{$key} = $entry;
		}
		if(defined @entry) {
		    push(@{$config{$key}}, @entry);
		}
		if(defined %entry) {
		    my($k);
		    foreach $k (keys %entry) {
			$config{$key}->{$k} = $entry{$k};
		    }
		}
	    }
	    print STDERR "*** Done examining ", $safe->root, "\n";
	    print STDERR "*** \%config after $ifile:\n";
	    main::dumpValue(\%config);
	    print STDERR "*** Done \%config after $ifile\n";
	}
    }
}

sub snarf_file {
    my($filename, $safe) = @_;

    if ($Safe::VERSION >= 2) {
	$safe->deny_only("system");
	$safe->permit("system");
    } else {
	$safe->mask($safe->emptymask());
    }

#    print STDERR "*** Pre-Dumping ", $safe->root, "($filename)\n";
#    main::dumpvar($safe->root);
#    print STDERR "*** Done pre-dumping ", $safe->root, "($filename)\n";

    $safe->rdo($filename);
    die "error: $@" if $@;

#    print STDERR "*** Dumping ", $safe->root, "($filename)\n";
#    main::dumpvar($safe->root);
#    print STDERR "*** Done dumping ", $safe->root, "($filename)\n";
}

sub parse_command_line {
    my ($snrub,$xyzzy);

    while(@ARGV) {
	if($ARGV[0] =~ /^-(s|server)$/) {
	    shift @ARGV; $config{server} = shift @ARGV; next;
	}
	if($ARGV[0] =~ /^-(p|port)$/) {
	    shift @ARGV; $config{port} = shift @ARGV; next;
	}
	if($ARGV[0] eq '-snrub') {
	    shift @ARGV; $snrub = 1; next;
	}
	if($ARGV[0] eq '-xyzzy') {
	    shift @ARGV; $xyzzy = 1; next;
	}
	if($ARGV[0] =~ /^-(\w+)=(\w+)$/) {
	    my($var,$val) = ($1,$2);
	    $config{$var} = $val;
	    shift @ARGV;
	}
	if($ARGV[0] =~ /^-(\w+)$/) {
	    my($var) = $1;
	    $config{$var} = 1;
	}
    }
#    GetOptions( 'm|mono!' => \$config{mono},
#	     's|server=s' => \$config{server},
#	       'p|port=i' => \$config{port},
#	        'pager=i' => \$config{pager},
#   	          'xyzzy' => \$xyzzy,
#            'zonedelta=i' => \$config{zonedelta},
# 	          'snrub' => \$snrub
#	       ) || die "\nUsage: $0 [-[m]ono] [-zonedelta <delta>] [-[s]erver servername] [-[p]ort number] [-pager 0|1]\n\n";

    if ($snrub) {
	print "Now is the time for all good women to foo their bars at their nation.  Random text is indeed random, and foo bar baz to you and me.  Bizboz, barf, fooble the toys.  Narf.  Feeb.  Frizt the cat.  There is a chair.  Behind the chair is a desk.  Atop the desk is a computer.  Before the computer is a Kosh.  Below the Kosh is a chair.\nPerl is a computer language used by computer geeks, hackers, users, administrators, and other people of all stripes.  It was written by Larry Wall, and has been hacked on by many, many others.  http://www.rpi.edu/~neild/pictures/hot-sex-gif.I-dare-you-to-work-out-how-to-wrap-this\n";
	exit(42);
    }	

    if ($xyzzy) {
	print "\nconfig options:\n";

	foreach (keys %config) { print "$_: $config{$_}\n"; }
	exit(0);
    }

}

sub collapse_list {
    my($lref) = @_;
    my($ext,%list);
    foreach $ext (@$lref) {
	if($ext =~ /^-(.*)$/) {
	    delete $list{$1};
	} else {
	    $list{$ext} = 1;
	}
	print STDERR "*** interim list ($ext)***\n";
	print STDERR join(", ",keys(%list)), "\n";
	print STDERR "*** Done interim list ***\n";
    }
    $lref = [keys %list];
}

sub config_ask {
	my($cmd) = @_;
	return (grep($_ eq $cmd, @{$config{slash}}));
}

sub Usage {
	print STDERR qq(
Usage: $0 [-m[ono]] [-zonedelta <delta>] [-[s]erver servername] [-[p]ort number] [-pager 0|1] [-<configvar>[=<configvalue>]\n";
);
}


1;
