# -*- Perl -*-
package LC::Event;

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
