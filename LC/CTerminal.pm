# -*- Perl -*-
package LC::CTerminal;

=head1 NAME

LC::CTerminal - curses-based terminal implementation

=head1 DESCRIPTION

The Terminal interface is an abstract interface to a character-based display
device.  It is intended to be replacable.  CTerminal is an implementation
of the Terminal interface using Curses.pm.

=head2 Attributes

Text output to the screen may be displayed with a variety of attributes.
See the term_getattr() and term_setattr() calls for information on accessing
attributes.  The following attributes are defined:

=over 10

=item bold

Bold text.  On a color terminal, selects bright color mode.

=item reverse

Inverse video.

=item normal

Neither bold, nor reversed.

=item fg:color, bg:color

Colored text is specified by attributes beginning with 'fg:' or 'bg:' (for
foreground and background colors, respectively.)  The following colors may
be used: black, red, green, yellow, blue, magenta, cyan, white.  A second
set of bright colors may be used (in the foreground only), by specifying
the 'bold' attribute.

=back

=head2 Character codes

Printable ('normal') characters entered by the user are returned as themselves.
Control characters are returned as 'C-c', where 'c' is the non-control version
of the character.  The following other mappings are defined:

    Down arrow  => 'kd'
    Up arrow    => 'ku'
    Left arrow  => 'kl'
    Right arrow => 'kr'
    Page up     => 'pgup'
    Page down   => 'pgdn'
    Backspace   => 'bs'
    Newline     => 'nl'

=head2 Variables

=over 10

=item $term_lines, $term_cols

The number of lines and columns available on the screen.

=back

=head2 Functions

All functions leave the cursor position unchanged unless otherwise
specified.  No function is required to have a visible effect until
term_refresh() is called.

=over 10

=item term_init()

This function must be called prior to any use of the screen.  It takes a
single parameter: a code reference which will be called when the terminal
is resized.

=item term_end()

This function shuts down the screen, and should be called prior to
ending the program.

=item term_clear()

Clears the screen.

=item term_getattr()

Returns a list describing the current screen attributes.  If this list
is passed to term_setattr() at a later time, the current attribute settings
will be restored.

=item term_setattr()

Takes a list of screen attributes to set.  Example:

    term_setattr('fg:white', 'bg:black', 'bold');

=item term_addstr()

Writes a string to the screen at the current cursor position.  The cursor
is moved to the end of the text added.  The result of  writing off the end of
a line is unspecified.  Example:

    term_addstr('Kakanakereba narimasen.');

=item term_move()

Sets the current cursor position.  The position is specified row first,
column second.  Example:

    # Move to the lower right corner of the screen.
    term_move($term_lines - 1, $term_cols - 1);

=item term_delete_to_end()

Clears all text from the current cursor position to the end of the line.

=item term_insert_line()

Inserts a line at the current cursor position.  All lines from the current
one to the end of the screen are shifted down one line.  The last line on
the screen vanishes.  The current line becomes blank.

=item term_delete_line()

Deletes the line at the current cursor position.  All lines from the one
subsequent to the current one to the end of the screen are shifted up one
line.  The last line of the screen becomes blank.

=item term_insert_char()

Inserts a character at the current cursor position.  All characters from the
current one to the end of the line are shifted right one character.  The
last character on the line disappears.  The current character position becomes
blank.

=item term_delete_char()

Deletes the character at the current cursor position.  All characters from
the one subsequent to the current one to the end of the line are shifted
left one line.  The last character on the line becomes blank.

=item term_get_char()

Returns the next character entered by the user (see 'Character codes' above),
if there is one, or undef otherwise.  This function does NOT block.

=item term_refresh()

Updates the screen with the most recent changes.

=item term_bell()

Sounds an audible bell.

=back

=cut


use Curses;
use POSIX;
use IO::Select;
use LC::Config;
eval "use Term::Size";
if ("$@") { 
  warn("** WARNING: Unable to load Term::Size **\n");
  sleep 2;
}

my $term_up = 0;
$size_changed = 0;
my $resize_cb;
my %attrs = ('bold' => 0,
	     'reverse' => 0,
	     'foreground' => 'black',
	     'background' => 'white');
my %colors = ('black'   => COLOR_BLACK,
	      'red'     => COLOR_RED,
	      'green'   => COLOR_GREEN,
	      'yellow'  => COLOR_YELLOW,
	      'blue'    => COLOR_BLUE,
	      'magenta' => COLOR_MAGENTA,
	      'cyan'    => COLOR_CYAN,
	      'white'   => COLOR_WHITE);
my %color_pairs = ('black:white' => 0);


sub term_cols { return $term_cols; }
sub term_lines { return $term_lines; }


sub new {
    bless {};
}


# Initialize the terminal.
sub term_init ($) {
    shift;
    return if ($term_up);
    $resize_cb = $_[0];
    ($ENV{COLUMNS}, $ENV{LINES}) = Term::Size::chars;
    initscr();
    #($COLS, $LINES) = Term::Size::chars;
    $term_lines = $LINES; 
    $term_cols = $COLS;
    noecho();
    cbreak();
    keypad(1);
    nodelay(1);
    #timeout(1000);
    $config{mono} = 1 unless (has_colors());
    start_color() unless ($config{mono});
    $SIG{WINCH} = sub { $size_changed = 1; };

    # If we don't specify this, curses may snarf characters before we ever
    # have a chance to notice them.
    typeahead(-1);

    $term_up = 1;
}


# End use of the terminal.
sub term_end () {
    shift;
    return unless ($term_up);
    undef $SIG{WINCH};
    endwin();
    %color_pairs = ('black:white' => 0);
    $term_up = 0;
}


# Gets the current attributes.
sub term_getattr ($) {
    shift;
    my @a = ('normal');
    push @a, 'bold' if ($attrs{'bold'});
    push @a, 'reverse' if ($attrs{'reverse'});
    push @a, "fg:$attrs{foreground}";
    push @a, "bg:$attrs{background}";
    return @a;
}


# Sets some attributes.
sub term_setattr (@_) {
    shift;
    my $newcol = 0;
    foreach (@_) {
	if ($_ eq 'bold') {
	    next if ($attrs{'bold'});
	    attron A_BOLD;
	    $attrs{'bold'} = 1;
	} elsif ($_ eq 'reverse') {
	    next if ($attrs{'reverse'});
	    attron A_REVERSE;
	    $attrs{'reverse'} = 1;
	} elsif ($_ eq 'normal') {
	    next unless ($attrs{'bold'} || $attrs{'reverse'});
	    attrset A_NORMAL | COLOR_PAIR(0);;
	    $attrs{'bold'} = 0;
	    $attrs{'reverse'} = 0;
	    $newcol = 1;
	} elsif (/fg:(.*)/) {
	    my $c = $1;
	    if (!defined $colors{$c}) {
		warn "Foreground color $c is unknown\n";
		next;
	    }
	    next if ($attrs{'foreground'} eq $c);
	    $attrs{'foreground'} = $c;
	    $newcol = 1;
	} elsif (/bg:(.*)/) {
	    my $c = $1;
	    if (!defined $colors{$c}) {
		warn "Background color $c is unknown\n";
		next;
	    }
	    next unless (defined $colors{$c});
	    next if ($attrs{'background'} eq $c);
	    $attrs{'background'} = $c;
	    $newcol = 1;
	}
    }

    if ($newcol) {
	my $pair = $attrs{'foreground'} . ':' . $attrs{'background'};
	my $id;
	if (defined $color_pairs{$pair}) {
	    $id = $color_pairs{$pair};
	} else {
	    $id = scalar(keys %color_pairs);
	    init_pair($id,
		      $colors{$attrs{'foreground'}},
		      $colors{$attrs{'background'}});
	    $color_pairs{$pair} = $id;
	}
	attron COLOR_PAIR($id);
    }
}


# Clears the screen.
sub term_clear () {
    shift;
    clear;
}


# Writes text using the current style at the current position.
sub term_addstr ($) {
    shift;
    addstr($_[0]);
}


# Repositions the cursor.
sub term_move ($$) {
    shift;
    my ($y,$x) = @_;
    move($y,$x);
}


# Deletes all characters to the end of line.
sub term_delete_to_end () {
    shift;
    clrtoeol();
}


# Inserts a new line at the current cursor position.
sub term_insert_line () {
    shift;
    insertln();
}


# Deletes the line at the current cursor position.
sub term_delete_line () {
    shift;
    deleteln();
}


# Inserts a character using the current style at the current cursor position.
sub term_insert_char () {
    shift;
    insch(' ');
}


# Deletes the character at the current cursor position.
sub term_delete_char () {
    shift;
    delch();
}


# Rings the terminal bell
sub term_bell () {
    shift;
    beep();
}

sub ALT_BACKSPACE () { return sprintf("%c",127); }

my %key_map = (&KEY_DOWN      => 'kd',
	       &KEY_UP        => 'ku',
	       &KEY_LEFT      => 'kl',
	       &KEY_RIGHT     => 'kr',
	       &KEY_PPAGE     => 'pgup',
	       &KEY_NPAGE     => 'pgdn',
	       &ALT_BACKSPACE => 'bs',     # fix for broken backspaces..
	       &KEY_BACKSPACE => 'bs',
	       "\n"           => 'nl',
	       "\r"           => 'nl');

# Returns a character if one is waiting, or undef otherwise.
my $metaflag = 0;
sub term_get_char () {
    my $self = shift;
    my $ch = getch;
    return undef if ($ch eq '-1');    

    if (ord($ch) == 27) {
	$metaflag = 1;
	return $self->term_get_char();
    }

    if ((ord($ch) >= 128) && (ord($ch) < 256)) {
	$ch = chr(ord($ch)-128);
	$metaflag = 1;
    }

    my $res;
    if (defined $key_map{$ch}) {
	$res = $key_map{$ch};
    } elsif (iscntrl($ch)) {
	$res = "C-" . chr(ord($ch) + ord('a') - 1);
    } else {
	$res = $ch;
    }

    $res = "M-" . $res if ($metaflag);

    $metaflag = 0;
    return $res;
}


# Redraws the screen.
sub term_refresh () {
    shift;
    refresh();
}


sub term_select ($$$$) {
    my $self = shift;
    my($rr, $wr, $er, $to) = @_;
 
    my $r = IO::Select->new(@$rr);
    my $w = IO::Select->new(@$wr);
    my $e = IO::Select->new(@$er);
    my @ret = IO::Select->select($r, $w, $e, $to);

    if ($size_changed) {
	$self->term_end();
	$self->term_init($resize_cb);
	&$resize_cb if (defined $resize_cb);
	$size_changed = 0;
    }

    return @ret;
}


1;
