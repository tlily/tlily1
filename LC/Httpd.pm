# -*- Perl -*-
# $Header: /data/cvs/tlily/LC/Httpd.pm,v 2.1 1998/12/08 21:46:15 steve Exp $
package LC::Httpd;

=head1 NAME

LC::Httpd - simple http daemon on the event queue

=head1 DESCRIPTION

This module implements a simple http daemon completely within tigerlily's
engine.  It is intended to be interfaced with extensions for client-to-client
communication, namely, file transfer.

This is the backend of the daemon.  All the parsing, etc is handled in an
extension.

=head2 External Functions

=over 10

=item close_webhandle()

Closes an open socket.  This function takes the handle passed via the
'httpdinput' event.

    close_webhandle($handle);

=back

=head2 Internal Functions

=over 10

=item httpd_listen()

Opens a socket, and listens on a port.  Returns the port number it is
listening on.  If there is already a socket open, this function will not
open another one, but will return the port number of the already used socket.

    httpd_listen();

=item httpd_shutdown()

Shuts down the server, closing all open connections, and closing the
listening socket.

    httpd_shutdown();

=item httpd_accept()

Function called by the event code to accept a new connection.  This should
not be called anywhere else.  The only argument is a reference to the event
handle.

    httpd_accept($handle);

=item httpd_process()

Function called by the event code on input from a connected client.  This
should not be called anywhere else.  The only argument is a reference to the
event handle.

    httpd_process($handle);

=back

=head1 EVENTS

=over 10

=item httpdinput

The 'Text' field is set to the data from the other client.  This is raw data,
and has not been parsed at all yet.

The 'Handle' field is the handle needed to call some of the low level
functions in this module.

=back

=cut

use Exporter;
use IO::Socket;
use Fcntl;

use LC::Event;
use LC::UI;
use LC::Config;

@ISA = qw(Exporter);

@EXPORT = qw(&close_webhandle
	     &httpd_error
	     &register_webfile
	     &deregister_webfile
	     &send_webfile
	     &httpd_date);

# $sock holds an IO::Socket object, if we have one.
# $port is the port that we're listening on, if we're listening at all.
my $sock, $port = 0;

# We want to be able to "shut down" if there is enough inactivity, so keep
# the handle we get back from register_iohandler() for the listening socket.
my $listenhandle;

# %fds contains the FileHandles for each socket.
# %handles is for keeping track of open sockets.
# They are hashed on $handle->{Id}.
my %fds, %handles;

# $timer is the handle to the timeout function.  it is deregistered if active
# when registering a new file to serve.
my $timer = 0;

# httpd_listen gets a port, and listens on it.

sub httpd_listen() {
    return $port if $port;

    # Find a port to bind to.
    $port = 31336;
    # Don't search forever, though.
    while (++$port < 32000) {
	last if $sock = new IO::Socket::INET ( LocalPort => $port,
					       Proto => 'tcp',
					       Listen => 5,
					       Reuse => 1,
					     );
    }
    return "Could not find a free port to bind to." unless $sock;

    # register the iohandler _before_ we listen, so we don't create a race.
    $listenhandle = register_iohandler( Handle => $sock,
					Mode => 'r',
					Call => \&httpd_accept
				      );

    ui_output("(Httpd.pm: listening on port $port)") if $config{debughttpd};

    if ((fcntl($listenhandle, F_SETFL(), O_NONBLOCK())) < 0) {
	ui_output("(Httpd.pm: W:unable to set nonblocking mode on socket: $!)");
    }

    # Success!
    return $port;
}

# httpd_accept() accepts an incoming connection

sub httpd_accept ($) {
    my ($handle) = @_;

    my $newsock;

    # A little sanity in this crazy world...
    return if $handle->{Id} != $listenhandle;

    $newsock = $sock->accept();

    ui_output("(Httpd.pm: accepted a connection)") if $config{debughttpd};

    # Get into nonblocking mode..
    if ((fcntl($newsock, F_SETFL(), O_NONBLOCK())) < 0) {
	ui_output("(Httpd.pm: W:Unable to set nonblocking mode on socket: $!)");
    }

    my $newh = register_iohandler ( Handle => $newsock,
				    Mode   => 'r',
				    Call   => \&httpd_process,
				  );

    $handles{$newh}++;
}

# httpd_process handles a connection after it's been accept()ed.

sub httpd_process ($) {
    my ($handle) = @_;

    my $fd = $handle->{Handle};
    ui_output ("(Httpd.pm: Processing handle $handle)") if $config{debughttpd};
    return unless ((ui_select([$fd], [], [], 0)));

    my $rc = sysread($fd, $buf, 4096);
    if ($rc < 0) {
	return if $errno == EAGAIN();
	close_webhandle ($handle);
	ui_output ("(Httpd.pm: Error reading from client: $!)")
	    if $config{debughttpd};
	return;
    }

    if ($rc == 0) {	# Closed connection
	close_webhandle ($handle);
	ui_output ("(Httpd.pm: Connection closed.)") if $config{debughttpd};
    }

    dispatch_event ( { Type => 'httpdinput',
		       Text => $buf,
		       Handle => $handle,
		       ToUser => 0,
		   } );
}

# Close a socket, and clean up.

sub close_webhandle ($) {
    my ($handle) = @_;

    ui_output("(Httpd.pm: Closing handle $handle)") if $config{debughttpd};
    deregister_handler ($handle->{Id});
    $handle->{Handle}->close();
    delete $handles{$handle->{Id}};
    return;
}

# Shutdown the server

sub httpd_shutdown () {
    return unless $port;

    ui_output("(Httpd.pm: Cleaning up)") if $config{debughttpd};
    $sock->close();
    deregister_handler($listenhandle);
    foreach $handle (keys (%handles)) {
	close_webhandle($handle);
    }
    $port = 0;
}


# The interface to the modules begins here.

# httpd_date returns a string based on the argument, or time(), if not provided

sub httpd_date(;$) {
    my ($time) = @_;

    $time = time() unless ($time);
    my ($sec, $min, $hour, $mday, $mon, $year, $wday) = gmtime($time);
    my $dayofweek = (qw(Mon Tue Wed Thu Fri Sat Sun))[$wday];
    my $month = (qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec))[$mon];

    $year += 1900;

    return sprintf "$dayofweek, %02d $month $year %02d:%02d:%02d GMT",
	$mday, $hour, $min, $sec;
}

sub httpd_error(%) {
    my (%args) = @_;

    my $fd = $args{Handle}->{Handle};

    print $fd "HTTP/1.0 ${args{ErrNo}} ${args{Title}}\r\n";
    print $fd "Date: " . httpd_date() . "\r\n";
    if (exists $args{Headers}) {
	foreach $header (keys (%{$args{Headers}})) {
	    print $fd "$header: $args{Headers}->{$header}\r\n";
	}
    }
    print $fd "\r\n";

    if ((!exists($args{Head})) || (!$args{Head})) {
	print $fd "<html><head>\n";
	print $fd "<title>${args{ErrNo}} ${args{Title}}</title>\n";
	print $fd "</head><body>\n<h1>${args{ErrNo}} ${args{Title}}</h1>\n";
	print $fd "${args{Long}}<p>\n";
	print $fd "</body></html>\n";
    }
#    close_webhandle($args{Handle});
    return;
}

sub register_webfile(%) {
    my (%args) = @_;

    unless ($config{debughttpd}) {
	return -1 unless -r $args{File};
    }

    # If there's a timer pending, stop it.
    deregister_handler($timer) if $timer;
    $timer = 0;

    if (defined ($args{Alias})) { 
	$files{$args{Alias}} = $args{File};
    } else {
	$files{$args{File}} = $args{File};
    }

    return $port if $port;
    return httpd_listen();
}

sub deregister_webfile($) {
    my ($file) = @_;

    delete $files{$file};

    if (!(%files)) {
	$timer = register_timedhandler(Interval => $config{httpdtimeout},
		   		       Call => sub { httpd_shutdown(); });
    }

    return;
}

sub send_rawfile($) {
    my ($handle) = @_;

    my $buf;

    my $fd = $handle->{Handle};
    if (read $handle->{Fd}, $buf, 4096) {
	print $fd $buf;
    } else {
	close_webhandle($handle->{WHand});
	close $handle->{Fd};
	deregister_handler($handle->{Id});
    }
}

sub send_webfile($$;$) {
    my ($file, $handle, $head) = @_;

    ui_output("(Httpd.pm: Requested file $file)") if $config{debughttpd};

    if ((!exists ($files{$file}))) {
	httpd_error( Handle => $handle,
		     ErrNo  => 404,
		     Title  => "File not found",
		     Long   => "The url $file is unavailable on this server.",
		     Head   => $head,
		   );
	return 0;
    }

    # Open the file, get the length, and set up (and send) the headers.
    if ((! -r $files{$file}) || !(open IN, $files{$file})) {
	httpd_error( Handle => $handle,
		     ErrNo  => 403,
		     Title  => "Forbidden",
		     Long   => "Unable to open $file.",
		     Head   => $head,
		   );
	return 0;
    }

    my $fd = $handle->{Handle};
    print $fd "HTTP/1.0 200 OK\r\n";
    print $fd "Date: " . httpd_date() . "\r\n";
    print $fd "Connection: close\r\n";
    print $fd "Content-Length: " . -s IN . "\r\n";
    print $fd "\r\n";

    # Then set up a iohandler to send the data itself in chunks.
    register_iohandler ( Handle => $fd,
			 WHand  => $handle,
			 Fd     => \*IN,
			 Mode   => 'w',
			 Call   => \&send_rawfile
		       );

    return 1;
}

1;
