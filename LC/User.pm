# -*- Perl -*-
package LC::User;

use Exporter;
use LC::UI;

@ISA = qw(Exporter);

@EXPORT = qw(&register_user_input_handler
	     &deregister_user_input_handler
	     &register_user_command_handler
	     &deregister_user_command_handler
	     &user_showline
	     &user_accept
	     &user_init
	     &help_get_list
	     &help_get_short
	     &help_get_long
	     &register_help_short
	     &register_help_long
	     );


@handlers = ();
%commands = ();
my $token = 0;


sub register_user_input_handler (&) {
    my($fn) = @_;
    $token++;
    push @handlers, [$token, $fn];
    return $token;
}


sub deregister_user_input_handler ($) {
    my($t) = @_;
    @handlers = grep { $_->[0] != $t } @handlers;
}


sub register_user_command_handler ($&) {
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

sub help_get_long {
    my($cmd) = @_;
    $cmd=~s/^\%//g;
    return $helplong{$cmd}
}

sub register_help_long {
    my($cmd,$help) = @_;
    $helplong{$cmd}=$help;
}


sub deregister_user_command_handler ($) {
    my($cmd) = @_;
    delete $commands{$cmd};
}


sub user_showline ($) {
    my($line) = @_;
    $line =~ s/[\<\\]/\\$&/g;
    ui_output("<usersend>" . $line . "</usersend>");
}


sub user_accept () {
    my @to_server = ();
  LINE:
    while (1) {
	my %iev = (Line => ui_process,
		   Server => 1,
		   UI => 1);
	last unless (defined $iev{Line});

	my $eh;
	foreach $eh (@handlers) {
	    my $f = $eh->[1];
	    my $r = &$f(\%iev);
	    next LINE if ($r);
	}

	user_showline($iev{Line}) if ($iev{UI});
	push @to_server, ($iev{Line} . "\r\n") if ($iev{Server});
    }

    return @to_server;
}


sub user_init () {
    register_user_input_handler(sub {
	my($iev) = @_;
	if ($iev->{Line} =~ /^%(\w*)\s*(.*)/) {
	    my($cmd, $args) = ($1, $2);
	    user_showline($iev->{Line});
	    if (defined $commands{$cmd}) {
		my $f = $commands{$cmd};
		&$f($args);
	    } else {
		ui_output("(The '$cmd' command is unknown.)");
	    }
	    return 1;
	}
    });
}


1;
