package LC::parse;                  # -*- Perl -*-

use Exporter;
use LC::status_update;
use LC::config;
use LC::UI;
use LC::log;
use POSIX;

@ISA = qw(Exporter);

@EXPORT = qw(&register_preparser
	     &deregister_preparser
	     &register_eventhandler
	     &deregister_eventhandler
	     &parse);


%time_prefixes = (' -> ' => 1,
		  ' <- ' => 1,
		  ' >> ' => 1,
		  ' \<\< ' => 1,
		  '# -> ' => 1,
		  '# \<- ' => 1,
		  '# >> ' => 1,
		  '# \<\< ' => 1,
		  '*** ' => 1,
		  '# *** ' => 1);


@prompts = ('-->\s*$',
	    '\(Y\/n\)\s*$',
            '^login:',
	    '^password:');


my $crumb = '';
my $msg_state = undef;
my $msg_sender;
my @msg_dest;

my @preparsers = ();
my $token = 0;

my %event_handlers = ();


sub register_preparser (&) {
    my($cmd) = @_;
    $token++;
    push @preparsers, [$token, $cmd];
    return $token;
}


sub deregister_preparser ($) {
    my($t) = @_;
    @preparsers = grep { $$_[0] != $t } @preparsers;
}


sub register_eventhandler ($&) {
    my($event, $cmd) = @_;

    $token++;
    push @{$event_handlers{$event}}, [$token, $cmd];
    return $token;
}


sub deregister_eventhandler ($$) {
    my($event, $t) = @_;
    @{$event_handlers{$event}} =
	grep { $$_[0] != $t } @{$event_handlers{$event}};
}


sub parse ($) {
    my($buf) = @_;

    # Divide into lines.
    $buf = $crumb . $buf;
    my @lines = split /\r?\n/, $buf, -1;
    $crumb = pop @lines;

    my $prompt;
    foreach $prompt (@prompts) {
	if ($crumb =~ /$prompt/) {
	    push @lines, $crumb;
	    $crumb = '';
	}
    }

    foreach (@lines) {
	dispatch_event(parse_line($_));
    }
}


sub dispatch_event ($) {
    my($event) = @_;

    my $pp;
    foreach $pp (@preparsers) {
	my $f = $$pp[1];
	&$f($_);
    }

    foreach $eh (@{$event_handlers{'all'}}) {
	my $f = $$eh[1];
	&$f($event);
    }

    if ($event->{Type}) {
	my $eh;
	foreach $eh (@{$event_handlers{$event->{Type}}}) {
	    my $f = $$eh[1];
	    &$f($event);
	}
    }

    return if ($event->{Invisible});

    ui_output($event->{Line});
}


sub parse_line ($) {
    my($line) = @_;
    $line =~ s/[\<\\]/\\$&/g;
    chomp $line;

    my $cmdid = undef;
    my $review = undef;
    my %event = ();


    # %server messages #######################################################

    # %begin, 2.2a1 cores.
    if ($line =~ /^%begin \((.*)\) \[(\d+)\]/) {
	$cmdid = $2;
	%event = (Type => 'begincmd',
		  Command => $1,
		  Invisible => 1);
	goto found;
    }

    # %begin, RPI core.
    if ($line =~ /^%begin \[(\d+)\] (.*)/) {
	$cmdid = $1;
	%event = (Type => 'begincmd',
		  Command => $2,
		  Invisible => 1);
	goto found;
    }

    # %command, all cores.
    if ($line =~ /^%command \[(\d+)\] (.*)/) {
	$cmdid = $1;
	$line = $2;
    }

    # %end, all cores.
    if ($line =~ /^%end \[(\d+)\]/) {
	$cmdid = $1;
	%event = (Type => 'endcmd',
		  Invisible => 1);
	goto found;
    }

    # %beginmsg
    if ($line =~ /^%beginmsg/) {
	%event = (Type => 'beginmsg',
		  Invisible => 1);
	goto found;
    }

    # %endmsg
    if ($line =~ /^%endmsg/) {
	%event = (Type => 'endmsg',
		  Invisible => 1);
	goto found;
    }

    # %connected
    if ($line =~ /^%connected/) {
	%event = (Type => 'connected');
	goto found;
    }

    # The options notification.  (OK, not a %command...but it fits here.)
    if ($line =~ /^\[Your options are/) {
	%event = (Type => 'options',
		  Invisible => 1);
	goto found;
    }

    if ($line =~ /^%/) {
	%event = (Type => 'servercmd');
	goto found;
    }


    # prompts ################################################################

    # All the other prompts.
    foreach (@prompts) {
	if ($line =~ /$_/) {
	    %event = (Type => 'prompt');
	    goto found;
	}
    }


    # /review ################################################################

    if (($line =~ /^\#\s*$/) ||
	($line =~ /^\#\s[\>\-\*\(]/) ||
	($line =~ /^\# \\\</)) {

	if (substr($line, 2, 1) eq '*') {
	    $line = substr($line, 2);
	    $review = '# ';
	} else {
	    $line = substr($line, 1);
	    $review = '#';
	}
    }


    # login stuff ############################################################

    # Welcome...
    if ($line =~ /^Welcome to lily at (.*)/) {
	my $s=$1;
	$s =~ s/\s*$//g;
	%event = (Type => 'welcome',
		  Server => $s);
	goto found;
    }


    # ( ) messages ###########################################################

    # your blurb has been set to...
    if ($line =~ /^\(your blurb has been set to \[(.*)\]\)/) {
	%event = (Type => 'blurb',
		  User => $me,
		  Blurb => $1);
	goto found;
    }    

    # your blurb has been turned off
    if ($line =~ /^\(your blurb has been turned off\)/) {
	%event = (Type => 'blurb',
		  User => $me,
		  Blurb => undef);
	goto found;
    }

    # you are now named...
    if ($line =~ /^\(you are now named \"(.*)\"/) {
	$me = $1;
	%event = (Type => 'rename',
		  User => $me,
		  To => $1);
	goto found;
    }    

    # you are now here
    if ($line =~ /^\(you are now here/) {
	%event = (Type => 'userstate',
		  User => $me,
		  From => 'away',
		  To => 'here');
	goto found;
    }

    # you are now away
    # you have idled away
    if ($line =~ /^\(you are now away/ ||
	$line =~ /^\(you have idled \"away\"/) {
	%event = (Type => 'userstate',
		  User => $me,
		  From => 'here',
		  To => 'away');
	goto found;
    }

    # you have created discussion...
    if ($line =~ /^\(you have created discussion (.*) \"/) {
	%event = (Type => 'disccreate',
		  Name => $1);
    }

    # you have destroyed discussion...
    if ($line =~ /^\(you have destroyed discussion (.*)\)/) {
	%event = (Type => 'discdestroy',
		  Name => $1);
    }

    # unknown parenthetical
    if ($line =~ /^\(/) {
	%event = (Type => 'parenthetical');
	goto found;
    }


    # sends ##################################################################

    # private headers
    if ($line =~ /^ >>/) { 
	my($blurb);

	if ($line =~ s|from ([^\[]*) \[(.*)\], to (.*):|from <sender>$1</sender> \[<blurb>$2</blurb>\], to <dest>$3</dest>:|) {
	    $msg_sender = $1;
	    $blurb = $2;
	    @msg_dest = split /, /, $3;
	} elsif ($line =~ s|from (.*), to (.*):|from <sender>$1</sender>, to <dest>$2</dest>:|) {
	    $msg_sender = $1;
	    $blurb = undef;
	    @msg_dest = split /, /, $3;
	} elsif ($line =~ s|from ([^\[]*) \[(.*)\]:|from <sender>$1</sender> \[<blurb>$2</blurb>\]:|) {
	    $msg_sender = $1;
	    $blurb = $2;
	    @msg_dest = ($me);
	} elsif ($line =~ s|from (.*):|from <sender>$1</sender>:|) {
	    $msg_sender = $1;
	    $blurb = undef;
	    @msg_dest = ($me);
	} else {
	    # Now what?
	    goto found;
	}

	%event = (Type => 'privhdr',
		  From => $msg_sender,
		  To => \@msg_dest);

	$msg_state = 'private';
	$line = "<privhdr>$line</privhdr>";
	goto found;
    }

    # public headers
    if ($line =~ /^ ->/) {
	my($blurb);

	if ($line =~ s|From ([^\[]*) \[(.*)\], to (.*):|From <sender>$1</sender> \[<blurb>$2</blurb>\], to <dest>$3</dest>:|) {
	    $msg_sender = $1;
	    $blurb = $2;
	    @msg_dest = split /, /, $3;
	} elsif ($line =~ s|From (.*), to (.*):|From <sender>$1</sender>, to <dest>$2</dest>:|) {
	    $msg_sender = $1;
	    $blurb = undef;
	    @msg_dest = split /, /, $3;
	} else {
	    # Now what?
	    goto found;
	}

	if (@msg_dest == 1) {
	    set_disc_state(Name => $msg_dest[0]);
	}

	%event = (Type => 'pubhdr',
		  From => $msg_sender,
		  To => \@msg_dest);

	$msg_state = 'public';
	$line = "<pubhdr>$line</pubhdr>";
	goto found;
    }

    # message body
    if ($line =~ /^ -/)  { 
	%event = (Type => 'send',
		  From => $msg_sender,
		  To => \@msg_dest,
		  Form => $msg_state);

	if ($msg_state eq 'private') {
	    $line = '<privmsg>' . $line . '</privmsg>';
	} elsif ($msg_state eq 'public') {
	    $line = '<pubmsg>' . $line . '</pubmsg>';
	}

	goto found;
    }


    # /who output ############################################################

    # /who header lines
    if ($line =~ /^  Name.*On Since/ ||
	$line =~ /^\s+----\s+--------\s+----\s+-----\s*$/) {

	%event = (Type => 'text',
		  For => 'who');
	goto found;
    }

    # /who information
    if (($line =~ /^[\>\<\| ][ \-\=\+][^\(]/) &&
	((substr($_, 57, 6) eq '  here') ||
	 (substr($_, 57, 6) eq '  away') ||
	 (substr($_, 57, 6) eq 'detach'))) {
	my($name, $blurb) = (undef, undef);
	my $state = substr($_, 57, 6);
	$state =~ s/^\s*//;

	if (substr($_, 2, 39) =~ /^([^\[]+) \[(.*)\]/) {
	    ($name, $blurb) = ($1, $2);
	} else {
	    $name = substr($_, 2, 39);
	    $name =~ s/^\s*//;
	    $name =~ s/\s*$//;
	    undef $name if (length($name) == 0);
	}

	if ($name) {
	    %event = (Type => 'who',
		      User => $name,
		      State => $state);
	    goto found;
	}
    }


    # /what output ###########################################################

    # /what header lines
    if ($line =~ /^  Name\s*Users\s*Idle/ ||
	$line =~ /^  ----    -----  ----  ---- -----/) {

	%event = (Type => 'text',
		  For => 'what');
	goto found;
    }

    # /what information
    if (($line =~ /^[\*\# ][ \+]\w/) && ((substr($_, 23, 1) eq 'c') ||
					 (substr($_, 23, 1) eq 'e'))) {
	my $name = substr($_, 2, 10);
	$name =~ s/\s*$//;
	my $type = (substr($_, 23, 1) eq 'c') ? 'connect' : 'emote';
	my $title = substr($_, 28);

	%event = (Type => 'what',
		  Disc => $name,
		  Disctype => $type,
		  Title => $title);
	goto found;
    }


    # /how output ############################################################

    # users information
    if ($line =~ /^Users:/) {
	$line =~
	    /^Users:\s+(\d+) Here;\s+(\d+) Away;\s+(\d+) Detached;\s+(\d+) Max/;
	my ($here,$away,$detached,$max) = ($1, $2, $3, $4);

	%event = (Type => 'howusers',
		  Here => $here,
		  Away => $away,
		  Detached => $detached,
		  Max => $max);
	goto found;
    }

    # discussions information
    if ($line =~ /^Discs:/) {
	$line =~ /^Discs:\s(\d+) Public;\s(\d+) Private;\s(\d+) Max/;
	my ($public,$private,$max) = ($1, $2, $3);

	%event = (Type => 'howusers',
		  Public => $public,
		  Private => $private,
		  Max => $max);
	goto found;
    }


    # emotes #################################################################

    # Emotes should be parsed up with the other sends, but there is a slight
    # problem.  Emotes begin with a '>'.  So do lines of /who output, if you
    # are ignoring someone.  Right now, I just do my best up in the /who
    # parser, and pray.  If you are a member of more than one emote, you
    # are fine -- the extra parentheses make things parsable.

    if ($line =~ /^> /) { 
	%event = (Type => 'emote');
	$line = '<emote>' . $line . '</emote>';
	goto found;
    }


    # *** notices ############################################################

    if ($line =~ /^\*\*\*/) {
	my $blurb = undef;

	$tline = $line;
	$tline =~ s/^\*\*\* //;
	$tline =~ s/^<time>\(\d\d:\d\d\)<\/time> //;

	if ($tline =~ s/ \[(.*)\]//) {
	    $blurb = $1;
	}

	# user state changes (lots of possibilities)
	my $newstate, $oldstate = (undef, undef);
	if ($tline =~ /^(.*) has detached/) {
	    $oldstate = undef;
	    $newstate = 'detach';
	} elsif ($tline =~ /^(.*) has been detached/) {
	    $oldstate = undef;
	    $newstate = 'detach';
	} elsif ($tline =~ /^(.*) has left lily/) {
	    $oldstate = undef;
	    $newstate = 'gone';
	} elsif ($tline =~ /^(.*) has idled to death/) {
	    $oldstate = undef;
	    $newstate = 'gone';
	} elsif ($tline =~ /^(.*) has idled \"away\"/) {
	    $oldstate = 'here';
	    $newstate = 'away';
	} elsif ($tline =~ /^(.*) is now \"away\"/) {
	    $oldstate = 'here';
	    $newstate = 'away';
	} elsif ($tline =~ /^(.*) has entered lily/) {
	    $oldstate = 'gone';
	    $newstate = 'here';
	} elsif ($tline =~ /^(.*) has reattached/) {
	    $oldstate = 'detach';
	    $newstate = 'here';
	} elsif ($tline =~ /^(.*) is now \"here\"/) {
	    $oldstate = 'away';
	    $newstate = 'here';
	}

	if ($newstate) {
	    %event = (Type => 'userstate',
		      User => $1,
		      From => $oldstate,
		      To => $newstate);
	    goto found;
	}

	# renames
	if ($tline =~ /^(.*) is now named (.*) \*\*\*/) {
	    %event = (Type => 'rename',
		      User => $1,
		      To => $2);
	    goto found;
	}

	# Discussion ... has been created
	if ($tline =~ /Discussion (.*), \".*\" has been created by (.*) \*\*\*/) {
	    %event = (Type => 'disccreate',
		      Name => $1);
	    goto found;
	}

	# You are now permitted to...
	if ($tline =~ /You are now permitted to (.*) \*\*\*/) {
	    %event = (Type => 'disccreate',
		      Name => $1);
	    goto found;
	}

	# Discussion ... has been destroyed
	if ($tline =~ /Discussion (.*) has been destroyed \*\*\*/) {
	    %event = (Type => 'discdestroy',
		      Name => $1);
	    goto found;
	}
    }


    # something completely unknown ###########################################

    %event = (Type => 'unparsed');


    # An event has been parsed.
  found:
    if ($review) {
	$line = '<review>' . $review . '</review>' . $line;
	$event{RevType} = $event{Type};
	$event{Type} = 'review';
    }

    $event{Id} = $cmdid;
    $event{Line} = $line;
    return \%event;
}


1;



