@@PERL@@
# $Header: /data/cvs/tlily/lilybot.PL,v 2.9 1999/02/05 22:41:17 josh Exp $

# This is the source to the bot running as "MechaJosh" on RPI-Lily.

require 5.00307;

$TL_ETCDIR="@@ETCDIR@@";
$TL_LIBDIR="@@LIBDIR@@";
$TL_EXTDIR="@@LIBEXTDIR@@";

use lib qw(@@LIBMODDIR@@);

use LC::Bot;

$|=1;

print "Username: ";
chomp($user=<STDIN>);
print "Password: ";
chomp($pass=<STDIN>);

bot_init();
bot_login($user,$pass);

register_bothandler(Match => "help",
		    Private => 1,
		    Respond => "Hi.. I know the following commands: cmd register [private] keyphase=response, cmd deregister #, cmd list, cmd show #, cmd <what you want me to do>.  Note that a \"response\" can contain perl code prefixed by \"CODE:\".  Its return value will be sent to the sender.  The original send will be in \$send.");

register_bothandler(Match => "grope",
		    Respond => "Me grope good!");		

register_bothandler(Match => "answer",
		    Respond => "The answer is 42, silly!");		

register_bothandler(Match => "excuse",
		    Respond => sub { 
			$exc=getquote("http://www.cae.wisc.edu/cgi-bin/ballard/bofhserver.pl");
			$exc =~ s/The cause of the problem is/Automatic Excuse/;		
			if ($exc =~ /\S/) {
			    return($exc);		
			} else {
			    return(undef);
			}
		    }
		    );

register_bothandler(Match => "surreal|weird|compliment",
		    Respond => sub {
			$comp=getquote("http://pharmdec.wustl.edu/cgi-bin/jardin_scripts/SCG");		
			if ($comp =~ /\S/) {
			    return($comp);		
			} else {
			    return(undef);
			}
		    }
		    );
		    
register_bothandler(Match => "search",
		    Respond => sub { getsearch(); }
		    );		    


bot_mainloop();


##############################################################################
sub getquote {
    my ($url)=@_;
    my ($ret,$p);

    open (E,"lynx -dump $url |");
    foreach (<E>) {
	if (/____/) {
	    $p=! defined($p);
	    next;
	}
	if (/^\s*$/) { next; }
	s/\s+/ /g;
	if ($p) { $ret .= $_; }
    }
    close(E);    

    $ret;
}

sub getsearch {
    my ($ret);

    for (1..5) {
      print "getting url\n";    
      open (E,"lynx -dump http://www.webcrawler.com/cgi-bin/SearchTicker|");
      $ret = <E>;
      $ret = <E>;
      $ret = <E>;
      $ret .= "... " . <E>;
      $ret .= "... " . <E>;
      $ret .= "... " . <E>;
      $ret .= "... " . <E>;
      $ret .= "... " . <E>;
      $ret .= "... " . <E>;      
      $ret =~ s/[\r\n]//g;
      close(E);
      last unless ($ret =~ /Choose a Channel/);
      sleep 1;      
    }
    $ret;
}

1;








