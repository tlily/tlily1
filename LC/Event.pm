# -*- Perl -*-
# $Header: /data/cvs/tlily/LC/Event.pm,v 2.5 1998/12/08 21:36:52 steve Exp $
package LC::Event;

# NOTES ON MEMORY LEAKS
# ---------------------
# I've experimented with some limited memory leak detection.  If you would like
# to try it, you need the following:
# perl 5.005 or greater.
# Devel::Leak
# set up the client to use UI-dummy to avoid UI memory leaks for now
# uncomment all the blocks marked "LEAKDEBUG" below.
# run tlily 2>/dev/null 

=head1 NAME

LC::Event - the event queue

=head1 SYNOPSIS

    use LC::Event;
    
    $id = register_eventhandler(Type => 'serverline',
				Order => 'after',
				Call => \&logger);

    dispatch_event({Type => 'serverline',
		   Text => $s});

    deregister_eventhandler($id);

=head1 DESCRIPTION

The Event module provides an event queue.  Event handlers may be
added and removed, and events transmitted.

=head2 The anatomy of an event handler

Event handlers are hashes of parameters.  An event handler has the following
defined parameters:

=over 10

=item Type

If specified, the handler will receive only events of this type.  If
not specified, the handler will receive all events.

=item Order

Event handlers run in three passes: before, during, and after.  All before
handlers will run before all during handlers, and all during handlers will
run before all after handlers.  No order of execution during a pass is
defined.  This parameter may be set to 'before', 'during', or 'after'.  If
it is left unset, it will default to 'during'.

=item Call

This parameter should be set to a code reference to execute when an event
is received.  This code will be called with two parameters: the first
is the event (a hash reference), and the second is a hash reference to
the event handler for which the code was invoked.  If this function
returns true, then no further event handlers will be processed for this
event.

=item Id

All event handlers are assigned a unique id when they are registered.  This
id is used to deregister a registered handler.  To make it easier for a
handler to deregister itself, the Id is added to the handler definition
when it is registered.

=back

=head2 The anatomy of an event

Events are hash references.  Only one field of an event is specified:
the 'Type' field controls which event handlers an event is transmitted to.

=head2 Functions

=over 10

=item register_eventhandler()

Registers a new event handler.  Takes an event handler (a hash of options)
as its parameter.  Example:

    $id = register_eventhandler(Type => 'serverline',
				Order => 'after',
				Call => \&logger);

=item deregister_eventhandler()

Identical to deregister_handler().  Depricated.

=item dispatch_event()

Transmits an event.  Takes an event (a hash reference) as its parameter.
Events are processed in the order they are received.  All event handlers
for a given event will run to completion before the next event is processed.
Example:

    dispatch_event({Type => 'serverline',
		   Text => $s});

=item register_iohandler()

Registers an I/O event handler.  Takes a hash as its paramter.  The hash
should contain "Handle", "Mode", and "Call" keys: Handle is a file handle
to monitor, Mode is any combination of the letters 'r', 'w', and 'e',
indicating that the handler should be invoked when the handle is readable,
writable, or has an exception flag, and Call is a reference to the code
to call when the event occurs.  (This code will be called with the
eventhandler as its argument.)
Example:

    register_iohandler(Handle => \*STDIN,
		       Mode => 'r',
		       Call => \&ui_process);

=item register_timedhandler()

Registers a timed event handler.  The event handler will be triggered
after a given number of seconds.  Takes a hash as its parameter.  The hash
should contain "Interval" and "Call" keys: Interval is the number of
seconds until the handler is invoked, and Call is a reference to the
code to call when the event occurs.  (This code will be called with the
eventhandler as its argument.)  If the "Repeat" key is set to a true
value, the handler will be invoked every Interval seconds until it is
deregistered; otherwise, it will be automatically deregistered after
its first invocation.
Example:

    register_timedhandler(Interval => 60,
			  Repeat => 1,
			  Call => \&update_clock);

=item deregister_handler()

Deregisters a handler.  Takes the id of a registered event handler.
While it is possible to deregister an event handler while in the middle of
event processing, the handler will still execute for the current event.
Example:

    deregister_handler($id);

=item event_loop()

Enters an event loop from which I/O and timed events are served.  This
function will never return (although exceptions may be thrown from within
it).

=back

=cut

#use Devel::Leak;  # LEAKDEBUG
use Carp;
use Exporter;
use IO::Select; 

use LC::Config;
BEGIN {
    if ($LC::UI::ui_loaded) {
	LC::UI->import();	
    } else {
	sub ui_select ($$$$) {
	    my($sel_r,$sel_w,$sel_e,$timeout)=@_;
	    my $rh = IO::Select->new(@$sel_r); 
	    my $wh = IO::Select->new(@$sel_w); 
	    my $eh = IO::Select->new(@$sel_e);  
	    return IO::Select->select($rh,$wh,$eh, $timeout); 
	}
    }
}


@ISA = qw(Exporter);

@EXPORT = qw(&register_eventhandler
	     &register_iohandler
	     &register_timedhandler
	     &deregister_handler
	     &deregister_all_handlers
	     &dispatch_event
	     &event_loop);


my @before_handlers = ();
my @during_handlers = ();
my @after_handlers = ();

my @io_handlers = ();

my $processing = 0;
my @event_queue = ();

my $token = 1;


sub register_eventhandler(%) {
    my(%h) = @_;

    $h{Id} = $token++;
    $h{Order} ||= 'during';
    if (!$h{Call}) {
	warn "Registering event handler (type = $h{Type}) with no callback.";
    }

    if ($h{Order} eq 'before') {
	push @before_handlers, \%h;
    } elsif ($h{Order} eq 'after') {
	push @after_handlers, \%h;
    } elsif ($h{Order} eq 'during') {
	push @during_handlers, \%h;
    } else {
	warn "Unknown priority for event handler: $h{Order}";
    }

    print STDERR "EV: registered: id=$h{Id}, o=$h{Order} t=$h{Type}\n"
	if ($config{edebug});

    return $h{Id};
}


sub deregister_handler($) {
    my($id) = @_;
    @before_handlers = grep { $_->{Id} != $id } @before_handlers;
    @during_handlers = grep { $_->{Id} != $id } @during_handlers;
    @after_handlers = grep { $_->{Id} != $id } @after_handlers;
    @io_handlers = grep { $_->{Id} != $id } @io_handlers;
    @time_handlers = grep { $_->{Id} != $id } @time_handlers;

    print STDERR "EV: deregistered: id=$h{Id}\n" if ($config{edebug});
}

sub register_iohandler(%) {
    my(%h) = @_;

    if (!defined($h{Handle})) {
	ui_output("*WARNING: register_iohandler called without Handle");
	return -1;	# Is this safe?
    }
    $h{Id} = $token++;
    $h{Mode} ||= "rwe";
    push @io_handlers, \%h;

    print STDERR "EV: reg io: id=$h{Id}\n" if ($config{edebug});

    return $h{Id};
}


sub register_timedhandler(%) {
    my(%h) = @_;

    $h{Id} = $token++;
    croak "Negative or zero interval.\n" if ($h{Interval} <= 0);
    $h{Time} = time + $h{Interval};
    push @time_handlers, \%h;

    print STDERR "EV: reg time: id=$h{Id} i=$h{Interval}\n"
	if ($config{edebug});

    return $h{Id};
}


sub dispatch_event($) {
    my($event) = @_;

    push @event_queue, $event;
    return if ($processing);

    $processing = 1;

    while (@event_queue) {
	transmit_event(shift @event_queue);
    }

    $processing = 0;
}


sub transmit_event($) {
    my($event) = @_;

    if ($config{edebug}) {
	print STDERR "EV: xmit: $event->{Type}";
	print STDERR " ", $event->{Text} if (defined $event->{Text});
	print STDERR "\n";
    }

    my @all_handlers = (@before_handlers, @during_handlers, @after_handlers);
    my $handler;
    foreach $handler (@all_handlers) {
	if ((!$handler->{Type}) || ($handler->{Type} eq $event->{Type})) {
	    print STDERR "    to: $handler->{Id} (t=$handler->{Type})\n"
		if ($config{edebug});
	    my $rc;
	    eval { $rc = &{$handler->{Call}}($event, $handler); };
	    if ($@) {
		warn("Event error: $@");
	    }
	    if (($rc != 0) && ($rc != 1)) {
		warn("Event handler $handler->{Id} ($handler->{Type}) returned $rc.");
	    }
	    print STDERR "        handler returned $rc\n"
		if ($rc && $config{edebug});
	    return if ($rc);
	}
    }
}


sub event_loop {
    while (1) {
	my(@sel_r, @sel_w, @sel_e);

	my $h;
	foreach $h (@io_handlers) {
	    push @sel_r, $h->{Handle} if (index($h->{Mode}, 'r') != -1);
	    push @sel_w, $h->{Handle} if (index($h->{Mode}, 'w') != -1);
	    push @sel_e, $h->{Handle} if (index($h->{Mode}, 'e') != -1);
	}

	my $now = time;
	my $timeout;

	my @new_ths;
	foreach $h (@time_handlers) {
	    if ($h->{Time} <= $now) {
		eval { my $rc = &{$h->{Call}}($h); };
		warn("Event error: $@") if ($@);
		if ($h->{Repeat}) {
		    $h->{Time} += $h->{Interval};
		    redo;
		}
	    } else {
		push @new_ths, $h;
		if ((!defined $timeout) || ($h->{Time} - $now < $timeout)) {
		    $timeout = $h->{Time} - $now;
		}
	    }
	}
	@time_handlers = @new_ths;

	print STDERR "Going into select: to = $timeout - \n"
	    if ($config{edebug});
	my($r, $w, $e) = ui_select(\@sel_r, \@sel_w, \@sel_e, $timeout);
	print STDERR "Exiting select.\n"
	    if ($config{edebug});
	
	#
	# What follows is really nasty.  Fix this, please.
	#

	my $fh;
	foreach $fh (@$r) {
	    foreach $h (@io_handlers) {
		if (fileno($fh) == fileno($h->{Handle})) {
		    if (index($h->{Mode}, 'r') != -1) {
			print STDERR "Readable on $h->{Handle}\n"
			   if ($config{edebug});
			   
			# LEAKDEBUG			   
#			my ($sv_count,$sv_count2); 
#			$sv_count = Devel::Leak::NoteSV($handle); 
			
			eval { my $rc = &{$h->{Call}}($h); };
			warn("Event error: $@") if ($@);
			
#			# LEAKDEBUG
#			$sv_count2 = Devel::Leak::CheckSV($handle);	
#			print "\n" . ("-" x 80) . 
#			      "\n<<<< io_handler: sv_count=$sv_count / sv_count2=$sv_count2 => (" . ($sv_count2-$sv_count) . " new)\n" .
#			      ("-" x 80) . "\n" if ($sv_count != $sv_count2);
		    }
		}
	    }
	}
	
	foreach $fh (@$w) {
	    foreach $h (@io_handlers) {
		if (fileno($fh) == fileno($h->{Handle})) {
		    if (index($h->{Mode}, 'w') != -1) {
			print STDERR "Writable on $h->{Handle}\n"
			    if ($config{edebug});
			eval { my $rc = &{$h->{Call}}($h); };
			warn("Event error: $@") if ($@);
		    }
		}
	    }
	}
	
	foreach $fh (@$e) {
	    foreach $h (@io_handlers) {
		if (fileno($fh) == fileno($h->{Handle})) {
		    if (index($h->{Mode}, 'e') != -1) {
			print STDERR "Exception on $h->{Handle}\n"
			    if ($config{edebug});
			eval { my $rc = &{$h->{Call}}($h); };
			warn("Event error: $@") if ($@);
		    }
		}
	    }
	}
    }
}


1;
