# -*- Perl -*-
package LC::User;

use Exporter;
use LC::UI;
use LC::Event;

@ISA = qw(Exporter);

@EXPORT = qw(&register_user_command_handler
	     &deregister_user_command_handler
	     &user_showline
	     &user_accept
	     &user_init
	     &user_password
	     &help_get_list
	     &help_get_short
	     &help_get_long
	     &register_help_short
	     &deregister_help_short
	     &register_help_long
	     &deregister_help_long
	     );


%commands = ();
my $token = 0;
my $password = 0;


sub register_user_command_handler($&) {
    my($cmd, $fn) = @_;
    $commands{$cmd} = $fn;
}


sub help_get_list {
    my %tmp;
    foreach ( keys %helpshort ) { $tmp{$_}=1; }
    foreach ( keys %helplong )  { $tmp{$_}=1; }
    foreach ( keys %commands )  { delete $tmp{$_}; $tmp{"%".$_}=1; }

    return sort keys %tmp;
}


sub help_get_short {
    my($cmd) = @_;
    $cmd=~s/^\%//g;
    return $helpshort{$cmd}
}


sub register_help_short {
    my($cmd,$help) = @_;
    $helpshort{$cmd}=$help;
}

sub deregister_help_short {
    my($cmd) = @_;
    delete $helpshort{$cmd};
}

sub help_get_long {
    my($cmd) = @_;
    $cmd=~s/^\%//g;
    return $helplong{$cmd}
}

sub register_help_long {
    my($cmd,$help) = @_;
    $helplong{$cmd}=$help;
}

sub deregister_help_long {
    my($cmd) = @_;
    delete $helplong{$cmd};
}


sub deregister_user_command_handler($) {
    my($cmd) = @_;
    delete $commands{$cmd};
}


sub user_showline($) {
    my($line) = @_;
    $line =~ s/[\<\\]/\\$&/g;
    ui_output("<usersend>" . $line . "</usersend>");
}


sub user_accept() {
    my @to_server = ();

    while (1) {
	my $text = ui_process();
	last unless (defined $text);
	user_showline($text) unless ($password);
	dispatch_event({Type => 'userinput',
			Text => $text . "\r\n",
			ToServer => 1});
    }

    return @to_server;
}


# Too many password state variables...this needs to be cleaned up.
sub user_password($) {
    $password = $_[0];
}


sub init() {
    register_eventhandler(Order => 'after',
			  Call => sub {
			      my($event,$handler) = @_;
			      if ($event->{ToUser}) {
				  ui_output($event->{Text});
			      }
			      if ($event->{Signal}) {
				  ui_bell();
			      }
			      return 0;
			  });

    register_eventhandler(Type => 'userinput',
			  Order => 'before',
			  Call => sub {
			      my($event,$handler) = @_;
			      if ($event->{Text} =~ /^%(\w*)\s*(.*?)\s*$/) {
				  my($cmd, $args) = ($1, $2);
				  $event->{ToServer} = 0;
				  if (defined $commands{$cmd}) {
				      my $f = $commands{$cmd};
				      &$f($args);
				  } else {
				      ui_output("(The '$cmd' command is unknown.)");
				  }
				  return 1;
			      }
			      return 0;
			  });
}

init();


1;
