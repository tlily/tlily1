# -*- Perl -*-
# $Header: /data/cvs/tlily/extensions/httpd.pl,v 2.2 1999/01/28 22:18:23 steve Exp $

=head1 NAME

extensions/httpd.pl - The parsing end to LC::Httpd.

=head1 DESCRIPTION

This is where all the parsing gets done for the http daemon.

=cut

# State variables.  These are used to keep track of what's going on in
# each connection.  The hashs (all of them?) are hashed on $handle->{Id}.
my %state;

# The partial part of the last chunk of data sent.
# This is wrong.
# my $partial = '';

# I have a bit of a quandry here.  httpd_parse() is the "right" place to
# handle a PUT, but it's completely possible that it has already split it
# into lines and passed it on to httpd_parse_line().  The options are to
# let it continue to do so, and reassemble in httpd_parse_line, but we
# then lose (a tiny bit of) information.  Another option would be to
# remove the "next if /\r?\n/;" line, which would pass an event for all the
# end of lines, as well, and then we get the last of our missing info.  The
# final option is to make httpd_parse a bit more intelligent about itself,
# and stop splitting into lines after seeing an empty line.  The line
# parser should not be interested in any of that, anyhow

# Break the input up into lines.
sub httpd_parse($$) {
    my ($event, $handle) = @_;
	
    # If we receive more data after a blank line, then it needs to get
    # either thrown out, or saved.
    if ($state{$event->{Handle}->{Id}}->{xDone}) {
		httpd_put($event, $handle);
		return;
    }
	
    my $partial = \$state{$event->{Handle}->{Id}}->{xPartial};
	
    my $text = $$partial . $event->{Text};
	
    my @lines = split /(\r?\n)/, $text;
	
    if (($$partial = pop @lines) =~ /(\r?\n)$/) {
		$$partial = '';
		push @lines, $1;
    }
	
    for (my $i = 0; $i <= $#lines; $i++) {
		next if $lines[$i] =~ /^\r?\n$/;
		dispatch_event( { Type   => 'httpdline',
						  Text   => $lines[$i],
						  Handle => $event->{Handle},
						  ToUser => 0,
						} );
		if ($lines[$i] eq '') {
			$state{$event->{Handle}->{Id}}->{xDone} = 1;
			# put the rest of the lines together
			$$partial = join ('', $lines[++$i..$#lines], $$partial);
			last;
		}
    }
}

# Sort of an event handler.  It doesn't run on an event, it's actually
# run during a special case of httpd_parse().  No reason to stick it back
# on the event queue.
sub httpd_put($$) {
    my ($event, $handle) = @_;
	
    my $st = \$state{$event->{Handle}->{Id}};
	
    if ($$st->{xCommand} eq 'PUTy') {
		if (!($$st->{xOut})) {
			my ($file) = ($$st->{xFile} =~ m|.+/(.+)$|);
			open OUT, ">$file";
			$$st->{xOut} = \*OUT;
			$$st->{xLength} = 0;
		}
		if ($$st->{xPartial} ne '') {
			print $$st->{xOut}, $$st->{xPartial};
			$$st->{xLength} += length $$st->{xPartial};
			$$st->{xPartial} = '';
		}
		if ($event->{Text}) { 
			print $$st->{xOut}, $event->{Text};
			$$st->{xLength} += length $event->{Text};
		}
		if ($$st->{Content-Length} &&
			($$st->{xLength} >= $$st->{Content-Length})) {
			cleanup($st);
		}
	}
	else {
		$$st->{xPartial} .= $event->{Text} if $event->{Text};
	}
}

sub httpd_parse_line($$) {
    my ($event, $handle) = @_;
	
    my $text = $event->{Text};
	
    my $st = \$state{$event->{Handle}->{Id}};
	
    ui_output("(httpd.pl: parsing line $text)") if $config{debughttpd};
	
    if (!($$st->{xCommand})) {
		if ($text !~ /^(\w+)[ \t]+(\S+)(?:[ \t]+(HTTP\/\d+\.\d+))?$/) {
			httpd_error( Handle => $event->{Handle},
						 ErrNo  => 400,
						 Title  => "Bad Request",
						 Long   => "This server did not understand that " .
						 "request." );
			close_webhandle($event->{Handle})
			  unless exists $event->{Handle}->{xPersist};
			cleanup ($st);
			return;
		}
		
		$$st = { xCommand  => $1,
				 xFile     => $2,
				 xProtocol => $3,
				 xId       => $event->{Handle}->{Id},
			   };
		
		# We're doing nothing at the moment..
		ui_output("(httpd.pl: Got a valid http request cmd: $1, file: $2)")
		  if $config{debughttpd};
		return;
    }
	
    if ($text =~ /^(\w+):(.+)$/) {
		$$st->{$1} = $2;
		return;
    }
	
    # End of headers.
    if ($text eq '') {
		if (($$st->{xCommand} ne 'GET') &&
			($$st->{xCommand} ne 'HEAD') &&
			($$st->{xCommand} ne 'PUT')) {
			httpd_error( Handle => $event->{Handle},
						 ErrNo  => 501,
						 Title  => "Not Implemented",
						 Long   => "This server did not understand that " .
						 "request." );
			close_webhandle($event->{Handle})
			  unless exists $event->{Handle}->{xPersist};
			cleanup($st);
			return;
		}
		
		# Special case for /
		if ($$st->{xFile} =~ m|^/$|) {
			my $fd = $event->{Handle}->{Handle};
			
			if ($$st->{xCommand} eq 'PUT') {
				httpd_error( Handle => $event->{Handle},
							 ErrNo  => 403,
							 Title  => "Forbidden",
							 Long   => "Access denied" );
				close_webhandle($event->{Handle})
				  unless exists $event->{Handle}->{xPersist};
				cleanup($st);
				return;
			}
			
			print $fd "HTTP/1.0 200 OK\r\n";
			print $fd "Date: " . httpd_date() . "\r\n";
			print $fd "Connection: close\r\n\r\n";
			if ($$st->{xCommand} eq 'GET') {
				print $fd "<html><head>\n<title>Tigerlily</title>\n";
				print $fd "</head><body>\n";
				print $fd "To download the lastest version of Tigerlily, ";
				print $fd "click ";
				print $fd "<a href=\"http://www.hitchhiker.org/tigerlily\">\n";
				print $fd "here</a>\n</body></html>\n";
			}
			close_webhandle($event->{Handle})
			  unless exists $event->{Handle}->{xPersist};
			cleanup($st);
			return;
		}
		
		$$st->{xFile} =~ s|/||;
		
		if ($$st->{xCommand} eq 'PUT') {
			unless (check_passive($$st->{xFile})) {
				httpd_error( Handle => $event->{Handle},
							 ErrNo  => 403,
							 Title  => "Forbidden",
							 Long   => "Access denied" );
				close_webhandle($event->{Handle})
				  unless exists $event->{Handle}->{xPersist};
				cleanup($st);
				return;
			}
			
			$$st->{xCommand} = 'PUTy';
			# Call httpd_put with dummy entrys to start everything.
			httpd_put ({ Handle => $event->{Handle} }, { });
			return;
		}
		
		unless (send_webfile($$st->{xFile}, $event->{Handle},
							 ($$st->{xCommand} eq 'HEAD'))) {
			close_webhandle($event->{Handle})
			  unless exists $event->{Handle}->{xPersist};
			cleanup($st);
			return;
		}
    }
}

sub httpd_close($$) {
	my ($event, $handle) = @_;
	
	cleanup (\$state{$event->{Handle}->{Id}});
}

# Before deleting a state, we need to make sure that anything that it
# has been using is also finished.
sub cleanup($) {
	my ($st) = @_;
	
	close $$st->{xOut} if exists $$st->{xOut};
	delete $state{$$st->{xId}};
}

sub unload() {
	deregister_webfile('xyz') if $config{debughttpd};
}

register_eventhandler( Type => 'httpdinput',
					   Call => \&httpd_parse );

register_eventhandler( Type => 'httpdline',
					   Call => \&httpd_parse_line );

register_eventhandler( Type => 'httpdclose',
					   Call =>&httpd_close );

$port = register_webfile( File => 'xyz' ) if $config{debughttpd};

1;
