# -*- Perl -*-
# $Header: /data/cvs/tlily/LC/User.pm,v 2.4 1998/12/07 22:37:56 neild Exp $
package LC::User;

use Exporter;
use LC::UI;
use LC::Event;
use Text::Abbrev;

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
%cmdAbbr = ();  # Command abbreviation hash
my $token = 0;
my $password = 0;
my $prompt = '';


sub register_user_command_handler($&) {
    my($cmd, $fn) = @_;
    $commands{$cmd} = $fn;
    # Rebuild command abbreviations hash.
    %cmdAbbr = abbrev keys %commands;
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
    # Rebuild command abbreviations hash.
    %cmdAbbr = abbrev keys %commands;
}


sub user_showline($) {
    my($line) = @_;
    $line =~ s/[\<\\]/\\$&/g;
    $prompt .= '<usersend>' . $line . '</usersend>' unless ($password);
    ui_output($prompt);
    $prompt = '';
}


sub user_accept() {
    while (1) {
	my $text = ui_process();
	last unless (defined $text);
	dispatch_event({Type => 'userinput',
			Text => $text,
			ToUser => 1,
			ToServer => 1});
    }
}


# Too many password state variables...this needs to be cleaned up.
sub user_password($) {
    $password = $_[0];
}


# Sends are wonky.
sub output_send($) {
    my($event) = @_;

    if ($event->{Emote}) {
	ui_output(Text => $event->{Body},
	          Target => $event->{Target},
	          WrapChar => $event->{WrapChar});
	return;
    }

    if ($event->{First}) {
	ui_output(Text => $event->{Text},
		  Target => $event->{Target},
		  WrapChar => $event->{WrapChar});
    }

    my $s;
    if ($event->{Form} eq 'private') {
	$s = '<privmsg> - ' . $event->{Body} . '</privmsg>';
    } else {
	$s = '<pubmsg> - ' . $event->{Body} . '</pubmsg>',
    }

    $s = '<review>#</review>' . $s if ($event->{Type} eq 'review');

    ui_output(Text => $s,
    	      Target => $event->{Target},	 
	      WrapChar => ' - ');
}


sub init() {
    register_eventhandler(Type => 'prompt',
			  Call => sub {
			      my($event,$handler) = @_;
			      $prompt = $event->{Text};
			      return 0;
			  });

    register_eventhandler(Order => 'after',
			  Call => sub {
			      my($event,$handler) = @_;
			      if ($event->{Signal}) {
				  ui_bell();
			      }
			      if ($event->{ToUser}) {
				  if (($event->{Type} eq 'send') ||
				      (($event->{Type} eq 'review') &&
				       ($event->{RevType} eq 'send'))) {
				      output_send($event);
				  } elsif ($event->{Type} eq 'userinput') {
				      user_showline($event->{Text});
				  }  elsif ($event->{Type} eq 'serverinput') {
				      my $s = $event->{Text};
				      $s =~ s/[\<\\]/\\$&/g;
				      ui_output($s);
				  } else {
				      ui_output(Text => $event->{Text},
						Target => $event->{Target},
						WrapChar =>
						$event->{WrapChar});
				  }
			      }
			      return 0;
			  });

    register_eventhandler(Type => 'ccommand',
			  Call => sub {
			      my($event,$handler) = @_;
			      $event->{ToServer} = 0;
			      my $command = $cmdAbbr{$event->{Command}};
			      if (defined $commands{$command}) {
				  my $f = $commands{$command};
				  &$f(join(' ', @{$event->{Args}}));
			      } else {
				  ui_output("(The '" . $event->{Command} .
					    "' command is unknown.)");
			      }
			  });
}

init();


1;
