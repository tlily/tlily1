# -*- Perl -*-
# $Header: /data/cvs/tlily/extensions/run_command.pl,v 1.4 1998/05/29 05:12:32 mjr Exp $

register_eventhandler(Type => "send",
		      Call => \&run_command_event);
register_user_command_handler('run_command', \&run_command_cmd);
register_help_short('run_command', "run a shell command for certain messages");
register_help_long('run_command', 
"Runs a given shell command when messages are received from a certain user.  The message body is passed to standard input of that command.

 usage: %run_command [user] [command]
        %run_command list
        %run_command clear
        %help [topic]");


sub run_command_event($$) {
    my($event,$handler) = @_;

    $from=$event->{From};
    $from=~tr/A-Z/a-z/;
    $msg=$event->{Text};
    $cmd=$run_cmd{$from};

    if ($cmd) {
	ui_output("* <white>[</white><yellow>$from</yellow><white>]</white> Running $cmd");
	open(CMD,"|$cmd 2>/dev/null >/dev/null");
	print CMD $msg;
	close(CMD);
    }		
    return 0;
}

sub run_command_cmd {
    my($args)=@_;

    if ($args =~ /^\s*$/) {
	ui_output("* usage: %run_command [user] [command]");
	ui_output("*      : %run_command list");
	ui_output("*      : %run_command clear");
	return;	   
    }

    if ($args =~ /^\s*list\s*$/) {
	ui_output("* The following commands are registered:");
	foreach (sort keys %run_cmd) {
	    ui_output(sprintf ("  %-10.10s %s",$_,$run_cmd{$_}));
	}
	return;	   
    }

    if ($args =~ /^\s*clear\s*$/) {
	ui_output("* Clearing commands");
	undef %run_cmd;
	return;
    }

    ($from,$cmd)=($args =~ /^\s*\"([^\"]*)\"\s+(.*)$/);
    if (! $from) {
	($from,$cmd)=($args =~/^\s*(\S+)\s+(.*)$/);
    }
    $from=~tr/A-Z/a-z/;
    
    $run_cmd{$from}=$cmd;
    ui_output("* Registered \'$cmd\' for messages from $from\n");
}




1;
