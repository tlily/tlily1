# -*- Perl -*-
# $Header: /data/cvs/tlily/LC/Server.pm,v 1.8 1998/05/29 05:12:20 mjr Exp $
package LC::Server;

use Exporter;
use LC::Event;
use IO::Socket;
use Fcntl;

@ISA = qw(Exporter);

@EXPORT = qw(&server_connect
	     &server_read
	     &server_send
	     $server_sock);

# Contact a lily server at a given host/port.
sub server_connect($$) {
    my($host, $port) = @_;

    $server_sock = IO::Socket::INET->new(PeerAddr => $host,
					 PeerPort => $port,
					 Proto    => 'tcp');
    if (!defined $server_sock) {
	die "Failed to contact server: $1\n";
    }

    fcntl($server_sock,F_SETFL,O_NONBLOCK) or die("fcntl: $!\n");
}


# Read a chunk of data from the lily server.
sub server_read() {
    my $buf;
    my $rc = sysread($server_sock,$buf,4096);
    if ($rc < 0) {
	if ($errno != EAGAIN) {
	    die("sysread: $!"); 
	}
    } elsif ($rc == 0) {
	$server_sock->close();
	return undef;
    }

    return $buf;
}


# Send a chunk of data to the server.
sub server_send($) {
    my($s) = @_;
    my $written = 0;
    while ($written < length($s)) {
	my $bytes = syswrite($server_sock,$s,length($s),$written);
	if (!defined $bytes) {
	    next if ($errno == EAGAIN);
	    die("syswrite: $!"); 
	    return;
	}
	$written += $bytes;
    }
}


# Register a handler to route data to the server.
sub init() {
    register_eventhandler(Order => 'after',
			  Call => sub {
			      my($event,$handler) = @_;
			      if ($event->{ToServer}) {
				  server_send($event->{Text});
				  server_send("\r\n");
			      }
			      return 0;
			  });
}

init();


1;
