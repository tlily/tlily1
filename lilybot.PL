@@PERL@@
# $Header: /data/cvs/tlily/lilybot.PL,v 1.2 1998/06/01 16:53:34 mjr Exp $

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
cmd_init();

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
			      if ($event->{Text} =~ /^login:/) {
				  print "FATAL: Error logging in.\n";
				  exit(0);
			      }
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
    
    if ($event->{ToUser}) {	
	if ($event->{Type} eq "send") {
	    if ($event->{Form} eq "private")   { 
		$to=$event->{From}; 		

		# back door..
		if ($event->{Raw} =~ /cmd (.*)/) {

		    my $cmdto=$event->{From}; 		
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
	    }
	    
	    # silly responses..
	    if ($event->{Raw} =~ /answer/i) {		
		response("$to;The answer is 42, silly!");		
	    }

	    if ($event->{Raw} =~ /grope/i) {
		response("$to;Me grope good!");		
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

1;


