@@PERL@@
# $Header: /data/cvs/tlily/lilybot.PL,v 2.4 1998/07/23 18:05:38 josh Exp $

require 5.00307;

$TL_ETCDIR="@@ETCDIR@@";
$TL_LIBDIR="@@LIBDIR@@";
$TL_EXTDIR="@@LIBEXTDIR@@";

use lib qw(@@LIBMODDIR@@);
BEGIN { $load_ui=0; }
use LC::Version;
use LC::Config;
use LC::Server;
use LC::Command;
use LC::Extend;
use LC::Event;
use LC::Client;
$|=1;

print "Username: ";
chomp($user=<STDIN>);
print "Password: ";
chomp($pass=<STDIN>);

config_init(); # should pass in config file name?
               # Maybe, but right now the list of config files is static.
cmd_init();

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

main();


##############################################################################


sub main() {
    # load the parser :)
    extension("parse");

    print("*** Connecting to $config{server} $config{port}.");
    server_connect($config{server}, $config{port});
    print("*** Connected.");

    client_init();

    # log in
    register_eventhandler(Type => 'prompt',
			  Order => 'before',
			  Call => sub {
			      my($event, $handler) = @_;
			      return 0 unless ($event->{Text} =~ /^login:/);
			      print("(logging in as $user $pass)\n");
			      server_send("$user $pass\n");
			      deregister_handler($handler->{Id});
			      return 1;
			  });

    # main event handler
    register_eventhandler(Order => 'after',
                          Call => \&eventhandler);

    # avoid prompts by hitting enter at all of them. 
    # (specific ones can be overridden)
    register_eventhandler(Type => 'prompt',
			  Order => 'after',
			  Call => sub {
			      my($event, $handler) = @_;
			      
			      print "$event->{Text}\n";
			      # if we see a login prompt at this point, 
			      # there was a problem logging in..
			      if ($event->{Text} =~ /^login:/) {
				  print "FATAL: Error logging in.\n";
				  exit(0);
			      }

			      # Try to avoid reviewing :)
			      if ($event->{Text} =~ /do you wish to review/) {
				  print "(review prompt, sending 'N')\n";
				  server_send("N\n");
				  return 1;
			      }
			      
			      # Fallback is to just hit enter at any prompt :)
			      print "(sending enter at prompt)\n";
			      server_send("\n");
			      return 1;
			  });
    
    while (1) {
	eval { event_loop(); };

	# Normal exit.
	if ($@ eq '') {
	    warn "*** Exiting.\n";
	    exit;
	}

	# Non-fatal errors.
	if ($@ =~ /^Undefined subroutine/) {
	    my $l = $@; $l =~ s/\\\</\\$@/g; chomp($l);
	    warn "ERROR: $l\n";
	    next;
	}
	
	# Oh, well.  Guess we have a problem.
	die $@;
    }
}

sub eventhandler {
    my($event,$handler) = @_;
    my($cmdto,$to);
    
    if ($event->{ToUser}) {	
	if ($event->{Type} eq "send") {
	    if ($event->{Form} eq "private")   { 
		$to=$event->{From}; 		
		$to=~ s/\s/_/g;

		# bot commands all begin with the prefix "cmd".
		if ($event->{Raw} =~ /cmd (.*)/) {
		    $cmdto=$event->{From};
		    $cmdto=~ s/\s/_/g;
		}

		if ($event->{Raw} =~ /cmd deregister (.*)/) {
		    my $id=$1;
		    if (deregister_bothandler($id)) {
			response("$cmdto;Deregistered handler $id.");
		    } else {
			response("$cmdto;Unable to deregister handler $id.");
		    }
		    return;
		} 

		if ($event->{Raw} =~ /cmd list/) {
		    my $ret="The following keywords are known: ";
		    foreach (sort keys %bot_handlers) {
			if ($bot_handlers{$_}->{Private}) {
			    $ret .= "$_) $bot_handlers{$_}->{Match} (private only) | ";
			} else {
			    $ret .= "$_) $bot_handlers{$_}->{Match} | ";
			}

		    }
		    response("$cmdto;$ret");			
		    return;		    
		} 
		
		if ($event->{Raw} =~ /cmd show (\d+)/) {
		    my $ret = "Handler $1 (matching $bot_handlers{$1}->{Match}): ";
		    $ret.=$bot_handlers{$1}->{Respond};
		    $ret=~s/[\n\r]/ /g;
		    response("$cmdto;$ret");
		    return;
		}

		if ($event->{Raw} =~ /cmd register private ([^\=]+)\=(.*)/) {
		    ($match,$respond)=($1,$2);

		    register_bothandler(Match => $match,
					Private => 1,
					Respond => $respond);
		    
		    response("$cmdto;Registered handler to match \"$match\". (in private sends only)");
		    return;
		}
		
		if ($event->{Raw} =~ /cmd register ([^\=]+)\=(.*)/) {
		    ($match,$respond)=($1,$2);

#XXX
		    response("$cmdto;Registering public handlers is not supported at this time.  Try cmd register private.");
		    return;
#XXX
		    register_bothandler(Match => $match,
					Respond => $respond);
		    
		    response("$cmdto;Registered handler to match \"$match\".");
		    return;
		}

		if ($event->{Raw} =~ /cmd (.*)/) {
		    cmd_process($1, sub {
			    my ($event) = @_;
			    
			    if ($event->{Type} eq "begincmd") {
				$buffer="";
				return; 
			    } 
			    
			    if ($event->{Type} eq "endcmd") { 
				$buffer=~s/[\r\n]/ /g;
				response("$cmdto;$buffer");
				$buffer="";
				return;
			    }
			    
			    $buffer .= $event->{Raw};
			});
		    return;
		}

	    } elsif ($event->{Form} eq "public") { 
		$to=join ',',@{$event->{To}}; 
		$to=~ s/\s/_/g;
	    }
	    
	    # ok, check for bot handlers that match this text..
	    foreach $h (values %bot_handlers) {
		if ($event->{Raw} =~ m/$h->{Match}/i) {
		    next if (($event->{Form} eq "public") && $h->{Private});

		    if (ref($h->{Respond})) {
			my $response=&{$h->{Respond}}($event->{Raw});
			response("$to;$response\n") if $response;
		    } elsif ($h->{Respond} =~ /^CODE: (.*)/) {
			$code=$h->{Respond};
			my $cpt=new Safe;
			my $send=$event->{Body}; $send=~s/[\r\n\']//g;
 			my $response=$cpt->reval("\$send='$send'; $code");
			$response=~s/[\r\n]//g;
			if ($@) {
			    response("$to;Error in eval: $@\n");
			} else {
			    response("$to;$response\n") if $response;
			}
		    } else {
			response("$to;$h->{Respond}");
		    }
		}
	    }
	}
	
	chomp($send=$event->{Raw});       
	print "$send\n";
    }          

    
}


sub response {
    ($string)=@_;
    print "(sending \"$string\" to server)\n";
    server_send("$string\n");
}

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


sub register_bothandler {
    my (%hdl)=@_;

    $bhid++;
    $bot_handlers{$bhid}=\%hdl;
}

sub deregister_bothandler {
    my ($bhid)=@_;

    if ($bot_handlers{$bhid}) {
	delete $bot_handlers{$bhid};
	return 1;
    } else {
	return 0;
    }
}

1;








