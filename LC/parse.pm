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
use LC::config;
use LC::UI;
use LC::log;
use LC::Event;
use POSIX;

@ISA = qw(Exporter);

@EXPORT = qw(&parse);


@prompts = ('-->\s*$',
	    '\(Y\/n\)\s*$',
            '^login:',
	    '^password:');

my $partial;

my $msg_state = undef;
my $msg_sender;
my @msg_dest;


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

    $line = $ev->{Text};
    $ev->{Raw} = $line;
    $line =~ s/[\<\\]/\\$&/g;
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
	$hidden = 1;
	%event = (Type => 'begincmd',
		  Command => $1);
	goto found;
    }

    # %begin, RPI core.
    if ($line =~ /^%begin \[(\d+)\] (.*)/) {
	$cmdid = $1;
	$hidden = 1;
	%event = (Type => 'begincmd',
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
	$hidden = 1;
	%event = (Type => 'endcmd');
	goto found;
    }

    # %beginmsg
    if ($line =~ /^%beginmsg/) {
	$hidden = 1;
	%event = (Type => 'beginmsg');
	goto found;
    }

    # %endmsg
    if ($line =~ /^%endmsg/) {
	$hidden = 1;
	%event = (Type => 'endmsg');
	goto found;
    }

    # %connected
    if ($line =~ /^%connected/) {
	$hidden = 1;
	%event = (Type => 'connected',
		Text => $line);
	goto found;
    }

    # %export_file
    if ($line =~ /^%export_file (\w+)/) {
	$hidden = 1;
	%event = (Type => 'export',
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
	$hidden = 1;
	%event = (Type => 'options');
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
		  Blurb => $1);
	goto found;
    }    

    # your blurb has been turned off
    if ($line =~ /^\(your blurb has been turned off\)/) {
	%event = (Type => 'blurb',
		  Blurb => undef);
	goto found;
    }

    # you are now named...
    if ($line =~ /^\(you are now named \"(.*)\"/) {
	%event = (Type => 'rename',
		  To => $1);
	goto found;
    }    

    # you are now here
    if ($line =~ /^\(you are now here/) {
	%event = (Type => 'userstate',
		  From => 'away',
		  To => 'here');
	goto found;
    }

    # you are now away
    # you have idled away
    if ($line =~ /^\(you are now away/ ||
	$line =~ /^\(you have idled \"away\"/) {
	%event = (Type => 'userstate',
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

    # you have created group...
    if ($line =~ /^\(you have created group \"(.*)\" with members (.*)\)/) {
	my @members = split /, /, $2;
	%event = (Type => 'group',
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
		  Group => $1);
	goto found;
    }

    # your group, "foo", now has members...
    # Please note that the first comma appears when adding members, but
    # not when deleting.  Augh.
    if ($line =~ /^\(your group,? \"(.*)\", now has members (.*)\)/) {
	my @members = split /, /, $2;
	%event = (Type => 'group',
		  Group => $1,
		  Members => \@members);
	goto found;
    }

    # unknown parenthetical
    if ($line =~ /^\(/) {
	%event = (Type => 'parenthetical');
	goto found;
    }


    # sends ##################################################################

    if (($line =~ /^ >>/) || ($line =~ /^ \\<\\</) ||
	($line =~ /^ ->/) || ($line =~ /^ \\<-/)) {
	my($blurb);

	if (defined $partial) {
	    $line = $partial . substr($line, 4);
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

	if (($line =~ /^ >>/) || ($line =~ /^ \\<\\</)) { 
	    # private headers
	    %event = (Type => 'privhdr',
		      From => $msg_sender,
		      To => \@msg_dest);

	    $msg_state = 'private';
	    $line = "<privhdr>$line</privhdr>";
	    goto found;
	} else {
	    # public headers
	    %event = (Type => 'pubhdr',
		      From => $msg_sender,
		      To => \@msg_dest);

	    $msg_state = 'public';
	    $line = "<pubhdr>$line</pubhdr>";
	    goto found;
	}
    }

    # message body
    if ($line =~ /^ - /)  { 
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
	((substr($line, 57, 6) eq '  here') ||
	 (substr($line, 57, 6) eq '  away') ||
	 (substr($line, 57, 6) eq 'detach'))) {
	my($name, $blurb) = (undef, undef);
	my $state = substr($line, 57, 6);
	$state =~ s/^\s*//;

	if (substr($line, 2, 39) =~ /^([^\[]+) \[(.*)\]/) {
	    ($name, $blurb) = ($1, $2);
	} else {
	    $name = substr($line, 2, 39);
	    $name =~ s/^\s*//;
	    $name =~ s/\s*$//;
	    undef $name if (length($name) == 0);
	}

	if ($name) {
	    %event = (Type => 'who',
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
		  For => 'what');
	goto found;
    }

    # /what information
    if (($line =~ /^[\*\# ][ \+]\w/) && ((substr($line, 23, 1) eq 'c') ||
					 (substr($line, 23, 1) eq 'e'))) {
	my $name = substr($line, 2, 10);
	$name =~ s/\s*$//;
	my $type = (substr($line, 23, 1) eq 'c') ? 'connect' : 'emote';
	my $title = substr($line, 28);

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
    }

    $event{ToUser} = 1 unless ($hidden);
    $event{Signal} = 'default' if ($signal);
    $event{Id} = $cmdid;
    $event{Text} = $line;
    
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



