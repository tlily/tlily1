# http daemon for tigerlily
# hopefully the beginnings of a CTC protocol.

# Bugs so far:
# The unload() sub doesn't actually close the listening socket, though it
#    should.  A strace shows an error of ENOTCONN.  I forget my networking!

use Socket;
use FileHandle;

my $sockfd, $port;
my $listenhandler;
# There is little to hash this on, so I will use an ever-increasing
# scalar to hash on.
my %cxns, %fds;

my $name = "deadbeef";

# This process accept()s an incoming connection
sub httpd_accept ($) {
    my ($hdr) = @_;

    return if $hdr->{Name} !~ /^Httpd$/;

    accept New, $sockfd;

    ui_output("(httpd: accepted a connection)");

    $newh = register_iohandler (Handle => \*New,
				Name => $name,
				Mode => 'r',
				Call => \&httpd_process);

    $fds{$name} = \*New;
    $cxns{$name++} = $newh;
}

sub httpd_process ($) {
    my ($handler) = @_;

    my $fd = $fds{$handler->{Name}};
    my $buf;
    my $s = new IO::Select;
    $s->add($fd);
    return if (! ($s->can_read(0)));

    my $rc = sysread($fd, $buf, 4096);
    if (($rc < 0)) {
	return if $errno == EAGAIN;
	close $fd;
	delete $cxns{$handler->{Name}};
	deregister_handler($handler);
	ui_output("(httpd: Error reading socket: $!)");
	return;
    }

# Closed connection
    if ($rc == 0) {
	close $fd;
	delete $cxns{$handler->{Name}};
	deregister_handler($handler);
	return;
    }


    foreach $line (split '[\r\n]', $buf) {
	httpd_parse($line, $handler);
    }
}

# Parse the incoming http request
sub httpd_parse ($$) {
    my ($line, $handler) = @_;
    my $fd = $fds{$handler->{Name}};

    ui_output ("(httpd: Processing line: $line)");

    # Simple parsing for now.  Just support GET
    if (my ($cmd, $file, $proto) = 
	($line !~ /^(\w+)[ \t]+(\S+)(?:[ \t]+(HTTP\/\d+\.\d+))?[^\012]*\012/)) {
	httpd_error($fd, "400 Bad Request");
    }
    ($cmd, $file, $proto) = ($1, $2, $3);
    ui_output ("(httpd: Cmd: $cmd; File: $file; Proto: $proto)");
    if ($cmd !~ /^GET$/) {
	print $fd "<html><head>\n<title>400 Bad Request</title>\n";
	print $fd "</head><body>\n<h1>Bad Request</h1>\n";
	print $fd "This server could not understand that request.<p>\n";
	print $fd "</body></html>\n";
	close $fd;
	delete $cxns{$handler->{Name}};
	deregister_handler($handler);
	return;
    }
}

sub httpd_error($$) {
    my ($fd, $error) = @_;
}

# Find a and bind to a socket
sub find_port ($) {
    my ($fd) = @_;

    $port = 31336;
    # Find a port, but don't search forever..
    while (++$port < 40000) {
	last if bind($fd, sockaddr_in($port, INADDR_ANY));
    }

    die "Could not find a port to bind to!" if $port >= 40000;
    ui_output("(httpd: listening on port $port)");
}

sub make_socket {
    
    socket(HTTPD, PF_INET, SOCK_STREAM, getprotobyname('tcp')) ||
	die "Error getting socket for httpd: $!";

    return \*HTTPD;
}

# Close the listening socket when unloading
sub unload {
    ui_output("(httpd: Cleaning up)");
    close($sockfd);
    deregister_handler($listenhandler);
    foreach $handler (keys (%cxns)) {
	close($fd{$handler});
	deregister_handler($cxns{$handler});
    }
}

# Initialize the module.  Get a socket, bind it, and start listening.
$sockfd = make_socket;
find_port($sockfd);

# Before we start listening, we want to set up the iohandler, so no
# connections get missed.
$listenhandler = register_iohandler( Handle => $sockfd,
				     Mode => 'r',
				     Name => "Httpd",
				     Call => \&httpd_accept);

# Now, it is ok to call listen() and get everything started
listen($sockfd, SOMAXCONN);
