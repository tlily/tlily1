package LC::parse;

use Exporter;
use LC::status_update;

@ISA = qw(Exporter);

@EXPORT = qw(&parse_servercmd &parse_output $parse_state $cli_command);


$cli_command=undef;
$parse_state=undef;
$sender=undef;      # sender as parsed from header
$privsender=undef;  # sender as recieved from %sender
$dest=undef;

tie $parse_state, 'LC::status_update', 'parse_state';

sub parse_output {
    ($output)=@_;

#    main::log_debug("parse_output: \"$output\"");
    foreach (split /\n/,$output) { parse_line($_); }

}

sub parse_line {
    ($line)=@_;
    $_=$line;
    
#    main::log_debug("parse_line: \"$line\"");

    # enter blurb ######################################################
    if (/^-->/) { $parse_state="blurb"; goto found;}
    # don't fall out prematurely.  try to stay in this state until
    # we're done answering questions.
    if ($parse_state eq "blurb" && /^Please/) { goto found; }
    if ($parse_state eq "blurb" && />>/)      { goto found; }

    # ( ) messages- one way out of the blurb state.
    # blurb changes ####################################################
    if (/^\(your blurb has been set to \[(.*)\]\)/) {
	&main::ui_status(blurb => $1);
	goto found;
    }    

    # pseudo changes ####################################################
    if (/^\(you are now named \"(.*)\"/) {
	&main::ui_status(pseudo => $1);
	goto found;
    }    

    # last login #######################################################
    # don't let this kick us out of the "login" state.
    if (/^\(last login/) { goto found; }

    # you were detached ################################################
    if (/^\(You were detached/) { $parse_state="reviewP"; goto found; }

    # other ()'s #######################################################
    # fall out to undef state.
    if (/^\(/) { $parse_state=undef; goto found; }

    # login process ####################################################
    # until we get to the "blurb" state, don't let it fall out of the
    # login state.
    if ($parse_state eq "login") { goto found; }

    # /review ##########################################################
    if (/^\#/) {
	$parse_state="review";
	goto found;
    }

    # private messages #################################################
    main::log_debug("$line");
    if (/^ >>/) { 
	my $blurb;

	$parse_state="privhdr"; 
	if (/message from (.*) \[(.*)\]:/) {
	    ($sender,$blurb)=($1,$2);
	} else {
	    ($sender)=/message from (.*):/;	
	    $blurb=undef;
	}
	$line=~s|from $sender|from <sender>$sender</sender>|;
	$line=~s|\[$blurb\]|\[<blurb>$blurb</blurb>\]|;
	goto found;
    }
    if (/^ -/ && $parse_state eq "privhdr")  { 
	$parse_state="privmsg";       
	goto found;
    }

    # public messages ##################################################
    if (/^ ->/) {
	$parse_state="pubhdr"; 

	my $blurb;
	if (/From (.*) \[(.*)\], to (.*):/) {
	    ($sender,$blurb,$dest)=($1,$2,$3);
	} else {
	    ($sender,$dest)=/From (.*), to (.*):/;
	}
	$line=~s|From $sender .* to $dest|From <sender>$sender</sender> to <dest>$dest</dest>|;
	$line=~s|\[$blurb\]|\[<blurb>$blurb</blurb\]|;
	goto found;
    }
    if (/^ -/ && $parse_state eq "pubhdr")  { 
	$parse_state="pubmsg";
	goto found;
    }

    # sanity checks ####################################################
    if (/^ -/ && ! ($parse_state =~ /(privhdr|privmsg|pubhdr|pubmsg)/)) {
	main::log_info("Warning: message body text out of context?");
    }

    # /who output ######################################################
    if (/Name.*On Since/) {
	if ($cli_command eq "who me") { $parse_state="who me"; return; }
	if ($cli_command =~ /who/)    { $parse_state="who";    return; }

	$parse_state="who";
	goto found;
    }
    if (/^\s+----/) {
	if ($parse_state =~ /who/ && $cli_command =~ /who/) { return; }
	goto found;
    }
    if ($parse_state eq "who me" && $cli_command eq "who me") {
	my $me=substr($_,0,40);
	my $blurb;
	$me =~s/^\s*//g;
	$me =~s/(\S)\s*$/$1/g;
	if ($me=~/\[(.*)\]/) {
	    $blurb=$1;
	    $me=~s/\[.*\]//g;
	}
	&main::ui_status(pseudo => $me, blurb => $blurb);
	$main::have_pseudo=1;
	$cli_command=undef;
	$parse_state=undef;
	return
    }

    # /how output ######################################################
    if (/^Users:/) {
	$parse_state="how";
	# output from /how, first line
	s/\s+/ /g;
	my ($here,$away,$detached,$max)=/^Users: (\d+) Here; (\d+) Away; (\d+) Detached; (\d+) Max/;
	&main::ui_status(here => $here,
			 away => $away,
			 detached => $detached,
			 max_users => $max);	    

	if ($cli_command eq "how") {
	    return;
	}
	goto found;
    }
    if (/^Discs:/) {
	# output from /how, first line
	s/\s+/ /g;
	my ($public,$private,$max)=/^Discs: (\d+) Public; (\d+) Private; (\d+) Max/;
	&main::ui_status(public => $public,
			 private => $private,
			 max_discs => $max);	    
	$parse_state=undef;
	if ($cli_command eq "how") {
	    undef $cli_command;	    
	    return;
	}
	goto found;
    }
    
    # default ################################################################
    # if we don't know what state we're in..
    if ($parse_state =~ /(who|what)/) {
	# we really don't know- until we hit something we recognize, stay 
        # in these states.
	goto found;
    }

    $parse_state=undef;
    
  found:     
    
    if (0) {
	if ($parse_state =~ /hdr/) {
	    $line =~ s/^ [->]> //g;
	    &main::ui_output("HDR: $line");
	    return;
	}
	if ($parse_state =~ /msg/) {
	    $line =~ s/^ - //g;
	    &main::ui_output("MSG: $line");
	    return;
	}
    }
    &main::ui_output($line);
}


# parse % commands from server.
sub parse_servercmd {
    ($_)=@_;

    # reset parse state when a server command is seen
    $parse_state=undef unless $parse_state=~/(login|blurb)/;
    
    # sender commands, send before private messages.
    if (/^%sender (.*)/) { $privsender=$1; return; }

    # beep commands
    if (/^%g/) { printf("\007"); return; }
    
    # default
    &main::log_info("SERVER: $_");
}

1;



