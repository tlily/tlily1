# -*- Perl -*-
# $header$
package LC::Client;

use LC::Event;
use LC::Server;


use Exporter;
@ISA=qw(Exporter);
@EXPORT=qw(&client_init &register_exithandler);
use vars qw($exit_handler);

sub register_exithandler {
    my ($handler)=@_;
    $exit_handler=$handler;
}

sub client_init() {
    my $state = 'login';
    my $set_opts = 0;

    register_iohandler(Handle => $main::server_sock,
		       Mode => 'r',
		       Name => 'a',
		       Call => \&server_reader);

    register_eventhandler(Call => sub {
	my($event,$handler) = @_;
	my $os = $state;
	if (($event->{Type} eq 'userinput') && ($state eq 'password')) {
	    $state = 'login';
	    $event->{ToUser} = 0;
	    ui_password(0);
	    user_password(0);
	} elsif (($event->{Type} eq 'userinput') && ($state eq 'blurb')) {
	    $state = 'cxna';
	} elsif (($event->{Type} eq 'userinput') && ($state eq 'reviewp')) {
	    $state = 'almostconnected';
	} elsif (($event->{Type} eq 'prompt') &&
		 ($event->{Text} =~ /^login:/)) {
	    set_client_options() unless ($set_opts);
	    $set_opts = 1;
	} elsif (($event->{Type} eq 'prompt') &&
		 ($event->{Text} =~ /^password:/)) {
	    $state = 'password';
	    ui_password(1);
	    user_password(1);
	} elsif (($event->{Type} eq 'prompt') &&
		 ($event->{Text} =~ /^-->/)) {
	    $state = 'blurb';
		set_client_options();
	} elsif (($state eq 'cxna') &&
		 ($event->{Type} eq 'serverline') &&
		 ($event->{Text} =~ /^Welcome to/)) {
	    $state = 'cxnb';
	} elsif (($state eq 'cxnb') &&
		 ($event->{Type} eq 'serverline')) {
	    $state = 'cxnc';
	} elsif (($state eq 'cxnc') &&
		 ($event->{Type} eq 'serverline') &&
		 ($event->{Text} =~ /\(Y\/n\)/)) {
	    $state = 'reviewp';
	} elsif (($state eq 'cxnc') &&
		 ($event->{Type} eq 'serverline')) {
	    $state = 'connected';
	} elsif ($event->{Type} eq 'connected') {
	    $state = 'connected';
	} elsif (($state eq 'almostconnected') &&
		 ($event->{Type} eq 'serverline')) {
	    $state = 'connected';
	}
	if ($state eq 'connected') {
	    deregister_handler($handler->{Id});
	    set_client_options();
	    dispatch_event({Type => 'connected',
			    Text => '%connected unknown'});
	}
	#ui_output("*** state: $os -> $state") if ($state ne $os);
	return 0;
    });
}


sub set_client_options() {
    #
    # Lily is gifted with a multitude of incompatible options.  What I have
    # here seems to work everywhere in use at the moment.  Someday, someone
    # will come along and break everything in the name of progress.  At this
    # point, I will declare lily dead, and get a life.
    #
    # The single, sole option which appears to work everywhere is `leaf'.
    # This gives me command leafing; the server will kindly identify
    # exactly what lines it sends to me are associated with what commands
    # I send to it.  This is insanely useful; I'm amazed it works.  (I had
    # begun to think that the server designers had intentionally designed
    # things to prevent anything useful from being usable.)
    #
    # Another REALLY useful option is `leaf-msg'.  It doesn't work right on
    # 2.2a1 cores.  In fact, enabling it there enables the new-style
    # protocol, which is buggy.  I therefore enable `leaf-all' (which, on
    # RPI core, enables `leaf-msg', among other things).  On 2.2a1 cores,
    # `leaf-all' doesn't exist, and therefore does nothing.  Upshot: we have
    # `leaf-msg' (a.k.a. %beginmsg/%endmsg support) on RPI core, but don't
    # count on it anywhere else.
    #
    # And then there's the `connected' option!  Ah, what I wouldn't do to
    # be able to use IT!  Unfortunately, it doesn't seem to work on 2.2a1.
    # I send it anyway, just for the hell of it.
    #

    server_send("\#\$\# client_version $TL_VERSION\n");
    server_send("\#\$\# client_name TigerLily\n");
    server_send("\#\$\# options +leaf-all +leaf +connected\n");
}


sub server_reader($) {
    my($handler) = @_;

    my $buf = server_read();
    if (!defined $buf) {

	&{$exit_handler} if ($exit_handler);

	dispatch_event({Type => 'disconnected'});
	deregister_handler($handler->{Id});
	return 0;
    }

    dispatch_event({Type => 'serverinput',
		    Text => $buf,
		    ToUser => 1});

    return 0;
}



1;
