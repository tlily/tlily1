# -*- Perl -*-

register_eventhandler(Type => "send",
		      Call => \&autoreply_event);
register_user_command_handler('autoreply', \&autoreply_cmd);
register_help_short('autoreply', "send a canned reply to private sends");
register_help_long('autoreply', 
"Sends an automated reply when private messages are received.

 usage: 
    %autoreply I'm not here right now, feel free to call me at my office, x7777.
    %autoreply |/usr/games/fortune -o
    %autoreply off
    %autoreply
");

$autoreply_status='';
register_statusline(Var => \$autoreply_status,
		    Position => "PACKLEFT");


sub autoreply_event {
    my($event,$handler) = @_;

    return 0 unless ($event->{Form} eq "private");
    
    $from=$event->{From};
    $from=~s/\s/_/g;
    if ($reply) {
        if (time()-$last_reply{$from} > 30) {
	    $last_reply{$from}=time();
	    if ($reply =~ /[\|\!](.*)/) {
	       $r=`$1`;
	       $r=~s/[\n\r\s]/ /g;
	    } else {
	       $r=$reply;
            }
	    ui_output("(sending automated reply to $from: \"$r\")");
	    $send_count++;
	    $autoreply_status="(autoreply $send_count)";
	    redraw_statusline();
	    server_send("$from:[automated reply] $r\r\n");
			   
        } else {
	    ui_output("(not sending a reply to $from, since one was sent in the last 30 seconds)");
	}
    }

    return 0;
}

sub autoreply_cmd {
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
       $send_count=0;
       $autoreply_status='';
       redraw_statusline();       
    } else {
       $send_count=0;
       $reply="@_";
       ui_output("(will send automated reply to private messages)");
       $autoreply_status="(autoreply $send_count)";
       redraw_statusline();
    }
}

1;
