package LC::parse;                  # -*- Perl -*-

use Exporter;
use LC::status_update;
use LC::Expand;
use LC::config;

@ISA = qw(Exporter);

@EXPORT = qw(&parse_servercmd &parse_output $parse_state $cli_command @info);

@info=();
$cli_command=undef;
$parse_state=undef;
$sender=undef;      # sender as parsed from header
$privsender=undef;  # sender as recieved from %sender
$dest=undef;

if ($main::debug) {
    tie $parse_state, 'LC::status_update', 'parse_state';
}

sub parse_output {
    ($output)=@_;

    foreach (split /\n/,$output) { parse_line($_); }

}

%time_prefixes = (' -> ' => 1,
		  ' <- ' => 1,
		  ' >> ' => 1,
		  ' \<\< ' => 1,
		  '# -> ' => 1,
		  '# \<- ' => 1,
		  '# >> ' => 1,
		  '# \<\< ' => 1,
		  '*** ' => 1,
		  '# ***' => 1);

sub parse_line {
    ($line)=@_;
    $line =~ s/[\<\\]/\\$&/g;
    $_=$line;
    
#    main::log_debug("parse_line: \"$line\"");

    # timezone munging #######################################################
    if (/^(.*?)\((\d\d):(\d\d)\)(.*)$/) {
	if ($time_prefixes{$1}) {
	    $hour = $2;
	    if ($config{'zonedelta'}) {
		$hour += $config{'zonedelta'};
	    }
	    $_ = $line = sprintf("%s<time>(%02d:%02d)</time>%s",
				 $1, $hour, $3, $4);
	}
    }

    # login stuff ############################################################
    if ($parse_state eq "login") {
	if ( /^Welcome to lily at (.*)/ ) {
	    my $s=$1;
	    $s=~s/\s*$//g;
	    &main::set_status( server => $s );
	}
    }

    # enter blurb ######################################################
    if (/^-->/) { $parse_state="blurb"; goto found;}
    # don't fall out prematurely.  try to stay in this state until
    # we're done answering questions.
    if ($parse_state eq "blurb" && /^Please/) { goto found; }
    if ($parse_state eq "blurb" && />>/)      { goto found; }

    # ( ) messages- one way out of the blurb state.
    # blurb changes ####################################################
    if (/^\(your blurb has been set to \[(.*)\]\)/) {
	&main::set_status(blurb => $1);
	goto found;
    }    

    if (/^\(your blurb has been turned off\)/) {
	&main::set_status(blurb => '');
    }

    # pseudo changes ####################################################
    if (/^\(you are now named \"(.*)\"/) {
	&main::set_status(pseudo => $1);
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
	$line="<review>$line</review>";
	goto found;
    }

    # private messages #################################################
    main::log_debug("$line");
    if (/^ >>/) { 
	my $blurb;

	if ($line =~ s|from ([^\[]*) \[(.*)\], to (.*):|from <sender>$1</sender> \[<blurb>$2</blurb>\], to <dest>$3</dest>:|) {
	    $sender = $1;
	} elsif ($line =~ s|from (.*), to (.*):|from <sender>$1</sender>, to <dest>$2</dest>:|) {
	    $sender = $1;
	} elsif ($line =~ s|from ([^\[]*) \[(.*)\]:|from <sender>$1</sender> \[<blurb>$2</blurb>\]:|) {
	    $sender = $1;
	} elsif ($line =~ s|from (.*):|from <sender>$1</sender>:|) {
	    $sender = $1;
	}

	$parse_state="privhdr"; 
	my $qsender = $sender; $qsender =~ s/\s/_/g;
	exp_set('sender', $qsender);
	$line="<privhdr>$line</privhdr>";
	goto found;
    }
    if (/^ -/ && $parse_state =~ /^priv/)  { 
	$parse_state="privmsg";  
	$line="<privmsg>$line</privmsg>";
	goto found;
    }

    # emotes ###########################################################
    if (/^> /) { 
	$parse_state="emote";
	$line="<emote>$line</emote>";
 	goto found;
    }

    # public messages ##################################################
    if (/^ ->/) {
	$parse_state="pubhdr"; 

	unless ($line =~ s|From ([^\[]*) \[(.*)\], to (.*):|From <sender>$1</sender> \[<blurb>$2</blurb>\], to <dest>$3</dest>:|) {
	    $line =~ s|From (.*), to (.*):|From <sender>$1</sender>, to <dest>$2</dest>:|;
	}
	$line="<pubhdr>$line</pubhdr>";
	goto found;
    }

    if (/^ -/ && $parse_state =~ /^pub/)  { 
	$parse_state="pubmsg";
	$line="<pubmsg>$line</pubmsg>";
	goto found;
    }

    # sanity checks ####################################################
#    if (/^ -/ && ! ($parse_state =~ /(privhdr|privmsg|pubhdr|pubmsg)/)) {
#	main::log_info("Warning: message body text out of context?");
#    }

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
	my $me=substr($_,2,29);
	my $blurb;
	$me =~s/^\s*//g;
	$me =~s/(\S)\s*$/$1/g;
	if ($me=~/\[(.*)\]/) {
	    $blurb=$1;
	    $me=~s/\[.*\]//g;
	}
	&main::set_status(pseudo => $me, blurb => $blurb);
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
	&main::set_status(here => $here,
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
	&main::set_status(public => $public,
			 private => $private,
			 max_discs => $max);	    
	$parse_state=undef;
	if ($cli_command eq "how") {
	    undef $cli_command;	    
	    return;
	}
	goto found;
    }
    
    
    # *** notices ############################################################
    if (/^\*\*\*/) {
	s/^\*\*\*//;
	if (/^(.*) has detached/) {
	  main::set_status( detached => "incr" );
	  main::set_status( here => "decr" );
	}
	if (/^(.*) has reattached/) {
	  main::set_status( detached => "decr" );
	  main::set_status( here => "incr" );
	}
	if (/^(.*) is now \"away\"/) {
	  main::set_status( here => "decr" );
	  main::set_status( away => "incr" );
	}
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
    if (/^%sender (.*)/) { exp_set('sender', $1); $privsender=$1; return; }

    # beginmsg commands
    if (/^%beginmsg/) { $parse_state="msg"; return; }
    if (/^%endmsg/) { $parse_state=undef; return; }

    # prompt
    if (/^%prompt/) { $parse_state = "prompt"; goto print_rest; }

    # connected.
    if (/^%connected/) { main::alarm_handler(); return; }

    # beep commands
    if (/^%g/) { ui_bell(); return; }

    # stupid thing we dont care about ;-)
    if (/%recip_regexp/) { return; }

    # export the info file woooo.
    if (/^%export_file OKAY/ && $cli_command eq "info set") {
	
	foreach (@info) { 
	    chomp;
	    main::send_to_server("$_\n");
	}
	undef $cli_command;	    
	return;
    }

    # export the info file.. it rejected me!  waaah!!
    if (/^%export_file NOT/) {	return; }

    # default
    &main::log_info("SERVER: $_");
    return;

  print_rest:
    s/^%\S+\s+//;
    s/^\[[^\]]*\]//;
    &main::ui_output($_);
}

1;



