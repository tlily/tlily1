# $Header: /data/cvs/tlily/extensions/irc.pl,v 2.1 1998/06/12 08:56:37 albert Exp $

register_user_command_handler('irc', \&irc);
register_help_short('irc', 'run dsirc as a \"sub client\"');
register_help_long('irc', ui_escape("usage:
    %irc <nick> <server>

Dsirc is a portion of the sirc irc client.  You must have sirc installed on
your system in order to use it!

http://www.eleves.ens.fr:8080/home/espel/sirc.html

"));

sub irc {
   
#    $ENV{SIRCLIB}=/path/to/dir.
    subclient_start(name=> "irc",
		    run => "dsirc -8 @_",
		    prefix => "<subc>irc></subc>",
		    filter => \&irc_filter,
		    onexit => \&cleanup);

    subclient_send("irc","\@ssfe\@\n");
   
    deregister_statusline($slid) if ($slid);

    $ircStatus="";

    $slid=register_statusline(Var => \$ircStatus,
			      Position => "PACKLEFT");
    
    1;
}

sub cleanup {
    $ircStatus="";
    redraw_statusline(1); 
    deregister_statusline($slid) if ($slid);
    redraw_statusline(1); 
}

sub irc_filter {
    my ($line)=@_;

    # escape < >
    $line=ui_escape($line);

    # process control characters
    # NOTE: We really have to trust that they are closed properly... grr.
    my $f=0;
    while ($line=~//) {
	if ($f) {
	    $line =~ s//<\/b>/;
	} else {
	    $line =~ s//<b>/;
	    $f=1;
	}
    }
    $f=0;
    while ($line=~//) {
	if ($f) {
	    $line =~ s//<\/reverse>/;
	} else {
	    $line =~ s//<reverse>/;
	    $f=1
	}
    }
    while ($line=~//) {
	if ($f) {
	    $line =~ s//<\/u>/;
	} else {
	    $line =~ s//<u>/;
	    $f=1
	}
    }

    # hook sirc's ssfe status into tlily's status bar
    ($status)=($line=~/`#ssfe#s(.*)$/);
    if ($status) { 
         $line =~ s/`#ssfe#.*$//g;
         $status=~s/\s+/ /g;
         $status=~s/^\s*//g;
         $ircStatus=$status;
         redraw_statusline(1); 
    }
    
    # remove other ssfe control codes.
    $line =~ s/`#ssfe#.//g;

    $line;
}


1;




