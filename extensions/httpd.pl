# http daemon for tigerlily
# hopefully the beginnings of a CTC protocol.

# Bugs so far:
# The unload() sub doesn't actually close the listening socket, though it
#    should.  A strace shows an error of ENOTCONN.  I forget my networking!

use Socket;
use FileHandle;

my $rawfd, $sockfd, $port;
my $listenhandler;
# Is there something to hash these on??
my %cxns;

# This process accept()s an incoming connection
sub httpd_accept ($) {
    my ($hdr) = @_;

    return if $hdr->{Name} !~ /^Httpd$/;

    accept New, $rawfd;

    ui_output("(httpd: accepted a connection)");

    my $fd = new FileHandle;
    my $newh;

    $fd->fdopen(New, "r");

    $newh = register_iohandler (Handle => $fd,
				RealHandle => \*New,
				Mode => 'r',
				Call => \&httpd_process);

    $cxns{\*New} = $newh;
}

sub httpd_process ($) {
    my ($handler) = @_;

    my $buf;
    my $s = new IO::Select;
    $s->add($handler->{RealHandle});
    return if (! ($s->can_read(0)));

    my $rc = sysread($handler->{$RealHandle}, $buf, 4096);
    if (($rc < 0)) {
	return if $errno == EAGAIN;
	close $handler->{$RealHandle};
	deregister_handler($handler);
	delete $cxns{$handler->{RealHandle}};
	ui_output("(httpd: Error reading socket: $!)");
	return;
    }

# Closed connection
    if ($rc == 0) {
	close $cxns{$handler};
	deregister_handler($handler);
	delete $cxns{$handler->{RealHandle}};
	ui_output("(httpd: closing connection)");
	return;
    }


    foreach $line (split '[\r\n]', $buf) {
	ui_output("(httpd: received line: $line)");
	httpd_parse($line);
    }
}

# Parse the incoming http request
sub httpd_parse ($) {
# It would be immensely useful to do something here.
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
    ui_output($port);
}

sub make_socket {
    
    socket(HTTPD, PF_INET, SOCK_STREAM, getprotobyname('tcp')) ||
	die "Error getting socket for httpd: $!";

    return \*HTTPD;
}

# Close the listening socket when unloading
sub unload {
    ui_output("(httpd: Cleaning up)");
    close($rawfd);
    deregister_handler($listenhandler);
    foreach $handler (keys (%cxns)) {
	close($cxns{$handler}->{RealHandle});
	deregister_handler($handler);
    }
}

# Initialize the module.  Get a socket, bind it, and start listening.
$rawfd = make_socket;
find_port($rawfd);

# We need a FileHandle for the iohandler, but we also need the raw socket for
# the socket functions.
$sockfd = new FileHandle;
$sockfd->fdopen($rawfd, "r");

# Before we start listening, we want to set up the iohandler, so no
# connections get missed.
$listenhandler = register_iohandler( Handle => $sockfd,
				     Mode => 'r',
				     Name => "Httpd",
				     Call => \&httpd_accept);

# Now, it is ok to call listen() and get everything started
listen($rawfd, SOMAXCONN);
