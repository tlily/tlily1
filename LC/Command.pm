# -*- Perl -*-
package LC::Command;

use Exporter;
use LC::parse;
use LC::log;

@ISA = qw(Exporter);

@EXPORT = qw(&cmd_init
	     &cmd_process);


%pending_commands = ();
%active_commands = ();


sub cmd_init () {
    register_eventhandler('begincmd', sub {
	my($e) = @_;
	my $cmd = $e->{Command};
	my $id = $e->{Id};
	if (defined $pending_commands{$cmd}) {
	    $active_commands{$id} = $pending_commands{$cmd};
	    delete $pending_commands{$cmd};
	}
    });

    register_eventhandler('all', sub {
	my($e) = @_;
	my $f = $active_commands{$e->{Id}};
	&$f($e) if (defined $f);
    });

    register_eventhandler('endcmd', sub {
	my($e) = @_;
	my $id = $e->{Id};
	if (defined $active_commands{$id}) {
	    delete $active_commands{$id};
	}
    });
}


sub cmd_process ($$) {
    my($c, $f) = @_;
    $pending_commands{$c} = $f;
    &main::send_to_server($c . "\n");
}


1;
