# -*- Perl -*-
package LC::config;

use Getopt::Long;
use FileHandle;
use Exporter;
use LC::log;
use LC::Extend;


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

sub dotfile_init {
    if ( -f "$ENV{HOME}/.lily/lclient/autologin" ) {
	#rpi lily.acm.rpi.edu 7777 user password
	my $f=new FileHandle("<$ENV{HOME}/.lily/lclient/autologin");
	if (defined $f) {
	    log_notice("Loading config from ~/.lily/lclient/autologin");
	    my ($l)=grep /\S/, grep ! /^\s*\#/, <$f>;
	    $l=~s/^\s*//g;
	    ($config{site},$config{server},$config{port},
	     $config{login},$config{password})=split /\s+/,$l;
	}
	
    }
    
    log_notice("(Searching ~/.lily/tlily/extensions for extensions)");
    foreach (grep /[^~]$/, glob "$ENV{HOME}/.lily/tlily/extensions/*.pl") {
	extension($_);
    }   

    log_notice("(Searching ", $main::TL_EXTDIR, " for extensions)");
    foreach (grep /[^~]$/, glob $main::TL_EXTDIR."/*.pl") {
	extension($_);
    }   

    # The init file should be used to configure the various extensions that 
    # have been loaded.
    if ( -f "$ENV{HOME}/.lily/tlily/init" ) {
	log_notice("Loading config from ~/.lily/tlily/init");
	extension("<$ENV{HOME}/.lily/tlily/init");
    } else {
	log_notice("(You may add perl code in ~/.lily/tlily/init)");
    }
}


1;
