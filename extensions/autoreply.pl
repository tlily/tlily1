# -*- Perl -*-

register_eventhandler(Type => "send",
		      Call => \&vacation_event);
register_user_command_handler('vacation', \&vacation_cmd);
register_help_short('vacation', "send a canned reply to private sends");
register_help_long('vacation', 
"Sends an automated reply when private messages are received.

 usage: 
    %vacation I'm not here right now, feel free to call me at my office, x7777.
    %vacation off
    %vacation
");


sub vacation_event {
    my($event,$handler) = @_;

    return 0 unless ($event->{Form} eq "private");
    
    $from=$event->{From};
    if ($reply) {
        if (time()-$last_reply{$from} > 30) {
	    $last_reply{$from}=time();
	    ui_output("(sending automated reply to $from)");
            server_send("$from:[automated reply] $reply\r\n");
        } else {
	    ui_output("(not sending a reply to $from, since one was sent in the last 30 seconds)");
	}
    }

    return 0;
}

sub vacation_cmd {
    ($cmd)=@_;
    if ($cmd eq "") {
       if ($reply) {
          ui_output("(current automated reply is \"$reply\")");
       } else {
          ui_output("(automated reply currently disabled)");
       }
    } elsif ($cmd eq "off") {
       $reply="";
       ui_output("(disabling automated reply to private messages)");       
    } else {
       $reply="@_";
       ui_output("(will send automated reply to private messages)");
    }
}

1;
