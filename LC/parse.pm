# -*- Perl -*-
package LC::parse;

=head1 NAME

LC::parse - The lily event parser

=head1 DESCRIPTION

The parse module translates all output from the server into internal
TigerLily events.  All server protocol support resides here.

Output enters the parse module through the parse() function (see below).
It then enters the event queue as a set of 'serverline' events, one for
each line of server output.  The parse module catches 'serverline' events
in the 'during' phase (so a 'before' handler can process these before
the parser), and generates appropriate events for each line.  See
the EVENTS section for a complete description of the generated events.

=head2 Functions

=over 10

=item parse()

Takes a chunk of raw server output, and processes it.  The output is
divided into lines, and a 'serverline' event is generated for each line.

=back

=head1 EVENTS

=head2 serverline

A 'serverline' event is generated for each line of output from the server.

=over 10

=item Text

The exact server output for the line.

=back

=cut


use Exporter;
use LC::UI;
use LC::Event;

@ISA = qw(Exporter);

@EXPORT = qw(&parse);


@prompts = ('-->\s*$',
	    '\(Y\/n\)\s*$',
            '^login:',
	    '^password:');

my $partial;

my $msg_state = undef;
my $msg_type = undef;
my $msg_sender;
my $msg_hdr = undef;
my $msg_wrapchar;
my @msg_dest;
my @msg_tags;
my $msg_raw;


# Take raw server output, and deal with it.
my $crumb = '';
sub parse($) {
    my($buf) = @_;

    # Divide into lines.
    $buf = $crumb . $buf;
    my @lines = split /\r?\n/, $buf, -1;
    $crumb = pop @lines;

    # Try to handle prompts; a prompt is a non-newline terminated line.
    # The difficulty is that we need to distinguish between prompts (which
    # are lines lacking newlines) and partial lines (which are lines which
    # we haven't completely read yet).
    my $prompt;
    foreach $prompt (@prompts) {
	if ($crumb =~ /$prompt/) {
	    push @lines, $crumb;
	    $crumb = '';
	}
    }

    # Spin off an event for each line.
    foreach (@lines) {
	dispatch_event({Type => 'serverline',
			Text => $_});
    }
}


# The big one: take a line from the server, and decide what it is.
sub parse_line($$) {
    my($ev, $h) = @_;

    my $raw  = $ev->{Text};
    my $warm = $ev->{Text};
    $warm =~ s/^%command \[\d+\] //;
    my $line = $ev->{Text};
    $line =~ s/([\<\\])/\\$1/g;
    chomp $line;

    my $signal = undef;
    my $cmdid = undef;
    my $review = undef;
    my $hidden = undef;
    my %event = ();


    # %server messages #######################################################
    # %begin, 2.2a1 cores.
    if ($line =~ /^%begin \((.*)\) \[(\d+)\]/) {
	$cmdid = $2;
	%event = (Type => 'begincmd',
		  Tags => ['intern'],
		  Command => $1);
	goto found;
    }

    # %begin, RPI core.
    if ($line =~ /^%begin \[(\d+)\] (.*)/) {
	$cmdid = $1;
	%event = (Type => 'begincmd',
		  Tags => ['intern'],
		  Command => $2);
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
		  Tags => ['intern']);
	goto found;
    }

    # %beginmsg
    if ($line =~ /^%beginmsg/) {
	$msg_state = 'msg';
	return 0;
    }

    # %endmsg
    if ($line =~ /^%endmsg/) {
	$line = $msg_hdr;
	%event = (Type => 'send',
		  Tags => [ @msg_tags ],
		  From => $msg_sender,
		  To => \@msg_dest,
		  Form => $msg_type,
		  Body => $partial,
		  WrapChar => $msg_wrapchar,
		  First => 1);
	undef $partial;
	undef $msg_state;
	goto found;
    }

    # %connected
    if ($line =~ /^%connected/) {
	%event = (Type => 'connected',
		  Tags => ['intern'],
		  Text => $line);
	goto found;
    }

    # %export_file
    if ($line =~ /^%export_file (\w+)/) {
	%event = (Type => 'export',
		  Tags => ['intern'],
		  Response => $1);
	goto found;
    }

    # %g
    if ($line =~ /^%g(.*)/) {
	$signal = 1;
	$line = $1;
    }

    # The options notification.  (OK, not a %command...but it fits here.)
    if ($line =~ /^\[Your options are/) {
	%event = (Type => 'options',
		  Tags => ['intern']);
	goto found;
    }

    if ($line =~ /^%/) {
	%event = (Type => 'servercmd');
	goto found;
    }


    # prompts ################################################################

    # All the other prompts.
    my $p;
    foreach $p (@prompts) {
	if ($line =~ /$p/) {
	    ui_prompt("$line");
	    %event = (Type => 'prompt');
	    $hidden = 1;
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
		  Tags => [ 'paren' ],
		  Blurb => $1);
	goto found;
    }    

    # your blurb has been turned off
    if ($line =~ /^\(your blurb has been turned off\)/) {
	%event = (Type => 'blurb',
		  Tags => [ 'paren' ],
		  Blurb => undef);
	goto found;
    }

    # you are now named...
    if ($line =~ /^\(you are now named \"(.*)\"/) {
	%event = (Type => 'rename',
		  Tags => [ 'paren' ],
		  To => $1);
	goto found;
    }    

    # you are now here
    if ($line =~ /^\(you are now here/) {
	%event = (Type => 'userstate',
		  Tags => [ 'paren' ],
		  From => 'away',
		  To => 'here');
	goto found;
    }

    # you are now away
    # you have idled away
    if ($line =~ /^\(you are now away/ ||
	$line =~ /^\(you have idled \"away\"/) {
	%event = (Type => 'userstate',
		  Tags => [ 'paren' ],
		  From => 'here',
		  To => 'away');
	goto found;
    }

    # you have created discussion...
    if ($line =~ /^\(you have created discussion (.*) \"/) {
	%event = (Type => 'disccreate',
		  Tags => [ 'paren' ],
		  Name => $1);
	goto found;
    }

    # you have destroyed discussion...
    if ($line =~ /^\(you have destroyed discussion (.*)\)/) {
	%event = (Type => 'discdestroy',
		  Tags => [ 'paren' ],
		  Name => $1);
	goto found;
    }

    # you have created group...
    if ($line =~ /^\(you have created group \"(.*)\" with members (.*)\)/) {
	my @members = split /, /, $2;
	%event = (Type => 'group',
		  Tags => [ 'paren' ],
		  Group => $1,
		  Members => \@members);
	goto found;
    }

    # you have deleted group...
    # you have destroyed group, ...
    # The first occurs after a /group kill, the second when you delete the
    # last member of a group.
    if (($line =~ /^\(you have deleted group \"(.*)\"\)/) ||
	($line =~ /^\(you have destroyed group, \"(.*)\"\)/)) {
	%event = (Type => 'group',
		  Tags => [ 'paren' ],
		  Group => $1);
	goto found;
    }

    # your group, "foo", now has members...
    # Please note that the first comma appears when adding members, but
    # not when deleting.  Augh.
    if ($line =~ /^\(your group,? \"(.*)\", now has members (.*)\)/) {
	my @members = split /, /, $2;
	%event = (Type => 'group',
		  Tags => [ 'paren' ],
		  Group => $1,
		  Members => \@members);
	goto found;
    }

    # unknown parenthetical
    if ($line =~ /^\(/) {
	%event = (Type => 'parenthetical',
		  Tags => [ 'paren' ]);
	goto found;
    }


    # sends ##################################################################

    if (($msg_state eq 'msg') && ($line =~ /^\s*$/)) {
	$partial = "\n";
	return 0;
    }

    if (($line =~ /^ >> /) || ($line =~ /^ \\<\\< /) ||
	($line =~ /^ -> /) || ($line =~ /^ \\<- /)) {
	my($blurb);

	if ($msg_state ne 'msg') {
	    $msg_state = 'first';
	    $msg_raw = $warm;
	} else {
	    $msg_raw .= "\n" . $warm;
	}

	if (defined $partial) {
	    if (length($partial) > 5) {
		$line = $partial . substr($line, 4);
	    } else {
		$line = $partial . $line;
	    }
	    undef $partial;
	}

	if ($line !~ /:\s*$/) {
	    $partial = $line;
	    return 0;
	}

	if ($line =~ s|rom ([^\[]*) \[(.*)\], to (.*):|rom <sender>$1</sender> \[<blurb>$2</blurb>\], to <dest>$3</dest>:|) {
	    $msg_sender = $1;
	    $blurb = $2;
	    @msg_dest = split /, /, $3;
	} elsif ($line =~ s|rom (.*), to (.*):|rom <sender>$1</sender>, to <dest>$2</dest>:|) {
	    $msg_sender = $1;
	    $blurb = undef;
	    @msg_dest = split /, /, $2;
	} elsif ($line =~ s|rom ([^\[]*) \[(.*)\]:|rom <sender>$1</sender> \[<blurb>$2</blurb>\]:|) {
	    $msg_sender = $1;
	    $blurb = $2;
	    @msg_dest = ();
	} elsif ($line =~ s|rom (.*):|rom <sender>$1</sender>:|) {
	    $msg_sender = $1;
	    $blurb = undef;
	    @msg_dest = ();
	} else {
	    # Now what?
	    goto found;
	}

	@msg_tags = ( 'send', "from:$msg_sender", $msg_type );
	my $d;
	foreach $d (@msg_dest) {
	    push @msg_tags, "to:$d";
	}

	if (($line =~ /^\n?( >> )/) || ($line =~ /^\n?( \\<\\< )/)) { 
	    $msg_type = 'private';
	    $line = "<privhdr>$line</privhdr>";
	    $msg_wrapchar = $1;
	} elsif (($line =~ /^\n?( -> )/) || ($line =~ /^\n?( \\<- )/)) {
	    $msg_type = 'public';
	    $line = "<pubhdr>$line</pubhdr>";
	    $msg_wrapchar = $1;
	} else {
	    $msg_type = 'unknown';
	}

	# Oooh, a hack!
	$msg_wrapchar =~ s/\\//g;

	$msg_hdr = $line;
	return 0;
    }

    # message body
    if ($line =~ /^ - /)  { 
	$msg_raw .= "\n" . $warm;

	if ($msg_state eq 'msg') {
	    if (defined($partial)) {
		$partial .= substr($line, 3);
	    } else {
		$partial = substr($line, 3);
	    }
	    return 0;
	}

	%event = (Type => 'send',
		  Tags => [ @msg_tags ],
		  From => $msg_sender,
		  To => \@msg_dest,
		  Form => $msg_type,
		  WrapChar => $msg_wrapchar,
		  Body => substr($line, 3));

	if ($msg_state eq 'first') {
	    $event{First} = 1;
	    $line = $msg_hdr;
	    undef $partial;
	    undef $msg_state;
	} else {
	    $line = '';
	}

	goto found;
    }


    # /who output ############################################################

    # /who header lines
    if ($line =~ /^  Name.*On Since/ ||
	$line =~ /^\s+----\s+--------\s+----\s+-----\s*$/) {

	%event = (Type => 'text',
		  Tags => [ 'who' ],
		  For => 'who');
	goto found;
    }

    # /who information
    if (($line =~ /^[\>\<\| ][ \-\=\+][^\(]/) &&
	(length($warm) > 63) &&
	((substr($warm, 57, 6) eq '  here') ||
	 (substr($warm, 57, 6) eq '  away') ||
	 (substr($warm, 57, 6) eq 'detach'))) {
	my($name, $blurb) = (undef, undef);
	my $state = substr($warm, 57, 6);
	$state =~ s/^\s*//;

	if (substr($warm, 2, 39) =~ /^([^\[]+) \[(.*)\]/) {
	    ($name, $blurb) = ($1, $2);
	} else {
	    $name = substr($warm, 2, 39);
	    $name =~ s/^\s*//;
	    $name =~ s/\s*$//;
	    undef $name if (length($name) == 0);
	}

	if ($name) {
	    %event = (Type => 'who',
		      Tags => [ 'who' ],
		      User => $name,
		      Blurb => $blurb,
		      State => $state);
	    goto found;
	}
    }


    # /what output ###########################################################

    # /what header lines
    if ($line =~ /^  Name\s*Users\s*Idle/ ||
	$line =~ /^  ----    -----  ----  ---- -----/) {

	%event = (Type => 'text',
		  Tags => [ 'what' ],
		  For => 'what');
	goto found;
    }

    # /what information
    if (($line =~ /^[\*\# ][ \+]\w/) && ((substr($warm, 23, 1) eq 'c') ||
					 (substr($warm, 23, 1) eq 'e'))) {
	my $name = substr($warm, 2, 10);
	$name =~ s/\s*$//;
	my $type = (substr($warm, 23, 1) eq 'c') ? 'connect' : 'emote';
	my $title = substr($warm, 28);

	%event = (Type => 'what',
		  Tags => [ 'what' ],
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
		  Tags => [ 'send', 'emote' ],
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
	$tline =~ s/^\(\d\d:\d\d\) //;

	if ($tline =~ s/ \[(.*)\]//) {
	    $blurb = $1;
	}

	# user state changes (lots of possibilities)
	my($newstate, $oldstate)= (undef, undef);
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
		      From => $1,
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
	push @{$event{Tags}}, 'review';
	$event{WrapChar} = '# ' . ($event{WrapChar} || '');
    }

    $event{ToUser} = 1 unless ($hidden);
    $event{Signal} = 'default' if ($signal);
    $event{Id} = $cmdid;
    $event{Text} = $line;

    #
    # The "Raw" field contains the raw server output, except for the
    # "%command [\d+] " prefix.  For send events, the Raw field contains
    # all lines of both the header and the body, separated by newlines.
    # The Raw field is never terminated by a newline.
    #

    if (defined $msg_raw) {
	$event{Raw} = $msg_raw;
	undef $msg_raw;
    } else {
	$event{Raw} = $warm;
    }

    if (!defined $event{Tags}) {
	$event{Tags} = [ 'normal' ];
    }

    if ($cmdid) {
	push @{$event{Tags}}, "id:$cmdid";
    }
    
    dispatch_event(\%event);
    return 0;
}


sub init() {
    register_eventhandler(Type => 'serverline',
			  Call => \&parse_line);

#    register_eventhandler(Type => 'connected',
#			  Call => sub { push @prompts, '\* $'; 0; }); # '})
}

init();


1;



