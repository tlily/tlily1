# -*- Perl -*-
package LC::config;

use Getopt::Long;
use Exporter;
@ISA = qw(Exporter);

@EXPORT = qw(%config);

use strict;
use vars qw(%config);

sub init {
    my ($snrub,$xyzzy);

    # default values
    $config{server}='lily.acm.rpi.edu';
    $config{port}=7777;
    $config{mono}=0;
#   $config{spoof_lclient}=1; 
    $config{options_after_connect}=1;

    GetOptions( 'm|mono!' => \$config{mono},
	     's|server=s' => \$config{server},
	       'p|port=i' => \$config{port},
   	          'xyzzy' => \$xyzzy,
            'zonedelta=i' => \$config{zonedelta},
 	          'snrub' => \$snrub
	       ) || die "\nUsage: $0 [-[m]ono] [-zonedelta <delta>] [-[s]erver servername] [-[p]ort number]\n\n";

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

    1;
