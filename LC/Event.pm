# -*- Perl -*-
package LC::Event;

=head1 NAME

LC::Event - the event queue

=head1 SYNOPSIS

    use LC::Event;
    
    $id = register_eventhandler(Type => 'serverline',
				Order => 'after',
				Call => \&logger);

    dispatch_event(Type => 'serverline',
		   Text => $s);

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

Deregisters an event handler.  Takes the id of a registered event handler.
While it is possible to deregister an event handler while in the middle of
event processing, the handler will still execute for the current event.
Example:

    deregister_eventhandler($id);

=item dispatch_event()

Transmits an event.  Takes an event (a hash reference) as its parameter.
Events are processed in the order they are received.  All event handlers
for a given event will run to completion before the next event is processed.
Example:

    dispatch_event(Type => 'serverline',
		   Text => $s);

=back

=cut


use LC::log;
use LC::UI;
use Exporter;

@ISA = qw(Exporter);

@EXPORT = qw(&register_eventhandler
	     &deregister_eventhandler
	     &dispatch_event);


my @before_handlers = ();
my @during_handlers = ();
my @after_handlers = ();

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

    return $h{Id};
}


sub deregister_eventhandler($) {
    my($id) = @_;
    @before_handlers = grep { $_->{Id} != $id } @before_handlers;
    @during_handlers = grep { $_->{Id} != $id } @during_handlers;
    @after_handlers = grep { $_->{Id} != $id } @after_handlers;
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

    my @all_handlers = (@before_handlers, @during_handlers, @after_handlers);
    my $handler;
    foreach $handler (@all_handlers) {
	if ((!$handler->{Type}) || ($handler->{Type} eq $event->{Type})) {
	    eval { my $rc = &{$handler->{Call}}($event, $handler); };
	    if ($@) {
		warn("Event error: $@");
	    }
	    last if ($rc);
	}
    }
}


1;
