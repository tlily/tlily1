package LC::config;

use Getopt::Long;
use Exporter;
@ISA = qw(Exporter);

@EXPORT = qw(%config);

use strict;
use vars qw(%config);

sub init {
    my $xyzzy;

    # default values
    $config{server}='albert.einstein.to';
    #$config{server}='lily.acm.rpi.edu';
    $config{login}='wilmesj';  $config{pass}='borfument';
    $config{port}=7777;
    $config{mono}=0;
    
    $Getopt::Long::autoabrev=1;  # enable abreviations    
    GetOptions( 'mono!' => \$config{mono},
	     'server=s' => \$config{server},
	       'port=i' => \$config{port},
 	        'xyzzy' => \$xyzzy
	       ) || die "\nUsage: $0 [-[m]ono] [-[s]erver servername] [-[p]ort number]\n\n";


    if ($xyzzy) {
	foreach (keys %config) { print "$_: $config{$_}\n"; }
	exit(0);
    }
}

    1;
