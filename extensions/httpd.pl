# -*- Perl -*-
# $Header: /data/cvs/tlily/extensions/httpd.pl,v 1.5 1998/12/08 21:46:21 steve Exp $

=head1 NAME

extensions/httpd.pl - The parsing end to LC::Httpd.

=head1 DESCRIPTION

This is where all the parsing gets done for the http daemon.

=cut

# The partial part of the last chunk of data sent.
my $partial = '';

# Break the input up into lines.
sub httpd_parse($$) {
    my ($event, $handle) = @_;

    my $text = $partial . $event->{Text};

    my @lines = split /(\r?\n)/, $text;

    if (($partial = pop @lines) =~ /^\r?\n$/) {
	$partial = '';
    }

    foreach (@lines) {
	next if /^\r?\n$/;
	dispatch_event( { Type   => 'httpdline',
			  Text   => $_,
			  Handle => $event->{Handle},
			  ToUser => 0,
		      } );
    }
}

# State variables.  These are used to keep track of what's going on in
# each connection.  The hashs (all of them?) are hashed on $handle->{Id}.
my %state;

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
		unless exists $event->{Handle}->{Persist};
	    return;
	}

	$$st = { xCommand  => $1,
		 xFile     => $2,
		 xProtocol => $3, };

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
	if (($$st->{xCommand} !~ /^GET$/) && ($$st->{xCommand} !~ /^HEAD$/)) {
	    httpd_error( Handle => $event->{Handle},
			 ErrNo  => 501,
			 Title  => "Not Implemented",
			 Long   => "This server did not understand that " .
				   "request." );
	    close_webhandle($event->{Handle})
		unless exists $event->{Handle}->{Persist};
	    return;
	}

	# Special case for /
	if ($$st->{xFile} =~ m|^/$|) {
	    my $fd = $event->{Handle}->{Handle};

	    print $fd "HTTP/1.0 200 OK\r\n";
	    print $fd "Date: " . httpd_date() . "\r\n";
	    print $fd "Connection: close\r\n\r\n";
	    if ($$st->{xCommand} =~ /^GET$/) {
		print $fd "<html><head>\n<title>Tigerlily</title>\n";
		print $fd "</head><body>\n";
		print $fd "To download the lastest version of Tigerlily, ";
		print $fd "click ";
		print $fd "<a href=\"http://www.hitchhiker.org/tigerlily\">\n";
		print $fd "here</a>\n</body></html>\n";
	    }
	    close_webhandle($event->{Handle})
		unless exists $event->{Handle}->{Persist};
	    return;
	}

	$$st->{xFile} =~ s|/||;

	unless (send_webfile($$st->{xFile}, $event->{Handle},
	    ($$st->{xCommand} =~ /^HEAD$/))) {
	    close_webhandle($event->{Handle})
		unless exists $event->{Handle}->{Persist};
	}
    }
}

sub unload () {
    deregister_webfile('xyz') if $config{debughttpd};
}

register_eventhandler( Type => 'httpdinput',
		       Call => \&httpd_parse );

register_eventhandler( Type => 'httpdline',
		       Call => \&httpd_parse_line );

$port = register_webfile( File => 'xyz' ) if $config{debughttpd};

1;
