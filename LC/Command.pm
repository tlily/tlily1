# -*- Perl -*-
package LC::Command;

use Exporter;
use LC::Server;
use LC::parse;
use LC::Event;

@ISA = qw(Exporter);

@EXPORT = qw(&cmd_init
	     &cmd_process);


%pending_commands = ();
%active_commands = ();


sub cmd_init () {
    # The order of these handlers is important!

    register_eventhandler(Type => 'begincmd',
			  Call => sub {
	my($e) = @_;
	my $cmd = $e->{Command};
	my $id = $e->{Id};
	if (defined $pending_commands{$cmd}) {
	    $active_commands{$id} = $pending_commands{$cmd};
	    delete $pending_commands{$cmd};
	}
	return 0;
    });

    register_eventhandler(Call => sub {
	my($e) = @_;
	return 0 unless ($e->{Id});
	my $f = $active_commands{$e->{Id}};
	&$f($e) if (defined $f);
	return 0;
    });

    register_eventhandler(Type => 'endcmd',
			  Call => sub {
	my($e) = @_;
	my $id = $e->{Id};
	if (defined $active_commands{$id}) {
	    delete $active_commands{$id};
	}
	return 0;
    });
}


sub cmd_process ($$) {
    my($c, $f) = @_;
    $pending_commands{$c} = $f;
    server_send($c . "\r\n");
}


1;
