# -*- Perl -*-
package LC::UI;


=head1 NAME

LC::UI - User input/output layer.

=head1 SYNOPSIS

    ui_start();
    ui_output('foo');
    ui_end();

=head1 DESCRIPTION

The UI module provides an interface to the user.  It is intended to be
modular -- it should be possible to replace this module with one implementing
a different style of interface.  (Such as an X-based interface.)

This implementation of the UI module is targeted at simple text screens.
It uses an abstraction layer to access the screen, as defined by the
CTerminal module.  (Curses based, currently the only functioning implementation
of the terminal layer.)

=head2 Functions

=over 10

=item ui_start()

This function must be called prior to any other UI functions.  Once it has
been called, the terminal should be considered inaccessible (i.e., do not
use any print statements afterwards).

=item ui_end()

Must be called prior to exiting the program.  The terminal is again
accessible after this function is called.

=item ui_attr()

Defines an attribute tag.  Takes the name of the tag and a list of attributes
to associate with this name.  (See the CTerminal documentation for a list
of attributes.)

    ui_attr('b', 'bold');

=item ui_output()

Sends a line of output to the user.  There are two forms of this command
which may be used: one takes the line to send as its only argument, the
other takes a hash of parameters.  The line text is given in the 'Text'
parameter.

The passed line may contain HTML-style attribute tags, such as <b>.  All
tags used must be first defined with the ui_attr() function.  Text sent
with this function is drawn with the 'text_window' tag by default.

Backslashes may be used to quote '<' characters that do not begin
attribute tags.  Backslashes must themselves be quoted.

The text may contain embedded newlines.

The 'WrapChar' parameter may be given to specify a prefix to use for
wordwrapped lines of output.

    ui_output(' -> From <user>damien</user>');
    ui_output(Text => ' -> From <user>damien</user>',
	      WrapChar => ' -> ');

=item ui_status()

Sets the status line.  This text may contain attribute tags.  The status
line is drawn with the 'status_line' tag by default.

    ui_status('<suser>damien</suser>');

=item ui_process()

Handles user input.  Returns a single line of user input, if one is available,
or undef otherwise.

=item ui_callback()

Registers a user key callback handler.  Takes two arguments: a key, and
a code reference to call when that key is pressed.  The callback will
be called with three arguments: the key pressed, the current input line,
and the current position in the input line (as an index).  A callback
may return a list of three elements: the new input line, the new position,
and a flag.  If this flag is 0, no further action is taken.  If it is 1,
the input cursor is repositioned.  If it is 2, the input line is redrawn
and the cursor is repositioned.  A callback may return null, in which case
the input line remains unchanged.

Callbacks are called in the reverse order of definition.  A successful
return from a callback prevents all subsequent callbacks from running.

    # Turn |s into pipes.
    sub pipe_conv($$$) {
	my($key, $line, $pos) = @_;
	$line = substr($line, 0, $pos) . 'pipe' .
	    substr($line, $pos);
	return ($line, $pos + 4, 2);
    }
    ui_callback('|', \&pipe_conv);

=item ui_remove_callback()

Removes a currently registered user key callback handler.  Takes the
same arguments as ui_callback().

=item ui_bell()

Rings the terminal bell.

=item ui_password()

Turns password mode on and off.  When password mode is active, input does
not display on the input line, and lines are not saved in the input history.
Takes a boolean argument to specify if password mode should be turned on
or off.

    ui_password(1);  # Enable password mode.

=item ui_prompt()

Sets the input prompt.  The prompt is displayed as a prefix on the input
line.  The prompt is cleared after each line accepted from the user.

    ui_prompt("login: ");

=back

=head2 Variables

=over 10

=item $ui_cols

The width of the display in characters.  (The height is intentionally not
provided.)

=back

=cut


use Exporter;

use IO::Handle;
use POSIX;

use LC::Config;

@ISA = qw(Exporter);

@EXPORT = qw(&ui_start
	     &ui_end
	     &ui_attr
	     &ui_output
	     &ui_status
	     &ui_process
	     &ui_callback
	     &ui_remove_callback
	     &ui_bell
	     &ui_password
	     &ui_prompt
	     &ui_select
	     &ui_set
	     $ui_cols);

my $term;

my $ui_up = 0;

my $password = 0;

my $win_moremode = 0;

my $input_line = '';
my $input_prompt = '';
my $input_height = 1;
my $input_fline = 0;
my $input_pos = 0;

my @input_history = ('');
my $input_curhistory = 0;

my $input_killbuf = "";

my $input_pastemode = 0;

my $page_status = 'normal';
my $status_line = "";
my $status_intern = "";
my $status_update_time = 0;

my @accepted_lines = ();

my %key_trans = ('kl'   => [ \&input_left ],
		 'C-b'  => [ \&input_left ],
		 'kr'   => [ \&input_right ],
		 'C-f'  => [ \&input_right ],
		 'ku'   => [ \&input_prevhistory ],
		 'C-p'  => [ \&input_prevhistory ],
		 'kd'   => [ \&input_nexthistory ],
		 'C-n'  => [ \&input_nexthistory ],
		 'C-a'  => [ \&input_home ],
		 'C-e'  => [ \&input_end ],
		 'C-k'  => [ \&input_killtoend ],
		 'C-u'  => [ \&input_killtohome ],
		 'pgup' => [ \&input_pageup ],
		 'M-v'  => [ \&input_pageup ],
		 'pgdn' => [ \&input_pagedown ],
		 'C-v'  => [ \&input_pagedown ],
		 'M-<'  => [ \&input_scrollfirst ],
		 'M->'  => [ \&input_scrolllast ],
		 'C-t'  => [ \&input_twiddle ],
		 'nl'   => [ \&input_accept ],
		 'C-y'  => [ \&input_yank ],
		 'C-w'  => [ \&input_killword ],
		 'C-l'  => [ \&input_refresh ],
		 'M-l'  => [ \&input_pastemode ],
		 'C-d'  => [ \&input_del ],
		 'C-h'  => [ \&input_bs ],
		 'bs'   => [ \&input_bs ]
		 );

my %attr_list = ();
my %attr_cmap = ();
my @attr_stack = ();
my $attr_cur_bg = COLOR_BLACK;
my $attr_cur_fg = COLOR_WHITE;


#
# What is a line?  A line is a text string, with attached formatting
# information.  A single line may span multiple rows on the screen; if
# so, it must be word-wrapped.  The internal representation of a line
# separates the text and formatting information.  The formatting information
# is contained in a list.  This list is a sequence of formatting commands;
# any command may be followed by a set of arguments.  Possible commands are:
#   FOwrapchar <wrapchar>
#   FOwrap
#   FOnewline
#   FOattr <attr>
#   FOpopattr <attr>
#   FOtext <length>


my $FOnull     = 0;
my $FOwrapchar = 1;
my $FOwrap     = 2;
my $FOnewline  = 3;
my $FOattr     = 4;
my $FOpopattr  = 5;
my $FOtext     = 6;


# A list of lines in the text window.  These lines are stored unformatted.
my @text_lines = (" ");

# A list of formatting information for the text window.
my @text_fmts = ( [] );

# A list of tags to identify lines by.
my @text_tags = ();

# A list of line heights.  This is a cache; any line's height as stored
# in here may be undef.  (We don't seem to be able to my this one; we need
# to use it in a handler passed down to the terminal module.)
@text_heights = ();

# The line and row in said line which are anchored to the bottom of the
# text window.
my $text_l = 0;
my $text_r = 0;

# The number of rows which have been scrolled up since the user last
# examined the screen.
my $scrolled_rows = 0;

my @text_show_tags = ();
my @text_hide_tags = ();


sub min($$) {
    return ($_[0] > $_[1]) ? $_[1] : $_[0];
}


# Starts the curses UI.
sub ui_start() {
    $config{'terminal'} ||= 'LC::CTerminal';
    eval "use $config{'terminal'};";
    $term = $config{'terminal'}->new();
    $term->term_init(sub {
	$ui_cols = $term->term_cols;
	@text_heights = ();
	$text_r = 0;
	scroll_info();
	$status_update_time = 0;
	&redraw;
    });
    $ui_cols = $term->term_cols;
    &redraw;
}


# Terminates the UI.
sub ui_end() {
    $term->term_end();
}


# Define a new attribute.
sub ui_attr($@) {
    my ($name,@attrs) = @_;
    $attr_list{$name} = \@attrs;
}


# Selects an attribute for use.
sub attr_use($) {
    my($name) = @_;

    my @curattrs = $term->term_getattr();
    push @attr_stack, \@curattrs;

    return if (!defined $attr_list{$name});

    my $attrs = $attr_list{$name};
    $term->term_setattr(@$attrs);
}


# Pops attribute usage stack.
sub attr_pop() {
    my $attrs = pop @attr_stack;
    $term->term_setattr(@$attrs);
}


# Rolls out the attribute stack.
sub attr_top() {
    my $attrs;
    while (@attr_stack) {
	$attrs = pop @attr_stack;
    }
    $term->term_setattr(@$attrs);
}


# Draws one line (or a subset of the rows in a line) at a given position.
sub win_draw_line($$$@) {
    my($ypos, $line, $fmt, $start, $count) = @_;

    my $p = 0;
    my $l = 0;
    my $x = 0;
    my $y = $ypos;
    my $wrapchar = '';

    attr_use('text_window');
    $term->term_move($y, 0);
    $term->term_delete_to_end();

    my $i;
    for ($i = 0; $i < scalar(@$fmt); $i++) {
	if ($fmt->[$i] == $FOwrapchar) {
	    $wrapchar = $fmt->[++$i];
	} elsif (($fmt->[$i] == $FOwrap) || ($fmt->[$i] == $FOnewline)) {
	    if (!defined($start) || ($l >= $start)) {
		$term->term_addstr(' ' x ($term->term_cols - $x));
	    }

	    $l++;
	    last if ((defined $count) && ($l >= $start + $count));
	    next if (defined($start) && ($l < $start));

	    unless (defined($start) && ($l == $start)) {
		$term->term_move(++$y, 0);
		$term->term_delete_to_end();
	    }

	    if ($fmt->[$i] == $FOwrap) {
		$term->term_addstr($wrapchar);
		$x = length $wrapchar;
	    } else {
		$x = 0;
	    }
	} elsif ($fmt->[$i] == $FOtext) {
	    $i++;
	    if ((!defined($start)) || ($l >= $start)) {
		$term->term_addstr(substr($line, $p,
				   (($fmt->[$i] < ($term->term_cols-$x)) ?
				    $fmt->[$i] : $term->term_cols - $x)));
		$x += $fmt->[$i];
	    }
	    $p += $fmt->[$i];
	} elsif ($fmt->[$i] == $FOattr) {
	    attr_use($fmt->[++$i]);
	} elsif ($fmt->[$i] == $FOpopattr) {
	    attr_pop();
	}
    }

    attr_top();
}

# fmtline is called with a line of <tag>formatted</tag> text.  It returns
# ($line, $fmt).
sub fmtline($) {
    my($text) = @_;

    $text =~ s/\\\\//g;
    $text =~ s/\\\<//g;
    $text =~ tr/</</;
    $text =~ s/\\(.)/$1/g;
    $text =~ tr//\\/;

    my $line = '';
    my @fmt = ();

    while (length $text) {
	if ($text =~ /^\/([^\>]*)\>/) {
	    # </tag>
	    $text = substr($text, length $&);
	    push @fmt, $FOpopattr;
	} elsif ($text =~ /^([^\>]*)\>/) {
	    # <tag>
	    $text = substr($text, length $&);
	    push @fmt, $FOattr, $1;
	} elsif ($text =~ /^\r?\n/) {
	    $text = substr($text, length $&);
	    push @fmt, $FOnewline;
	} elsif ($text =~ /^[^]+/) {
	    # text
	    $text = substr($text, length $&);
	    $line .= $&;
	    push @fmt, $FOtext, length $&;
	}
    }

    return ($line, \@fmt);
}


# This function performs line wrapping.  It takes an line and format pair,
# and returns the number of rows spanned by the line.  The format information
# is modified to break the line across rows.
sub line_wrap($$) {
    my($line, $fmt) = @_;

    # Tack a trailing element onto the format array.  This permits the loop
    # below to execute one more time, simplifying some of the logic.
    push @$fmt, $FOnull;

    # @fmt contains the NEW format information that we construct.  Perhaps
    # I should not have given it the same name as $fmt (the OLD format
    # information), but what is done is done.
    my @fmt = ();

    # $idx is an index into the string.  It marks the beginning of the text
    # that has not yet been packed into the new format string.
    my $idx = 0;

    # $x is the current column of the output cursor.
    my $x = 0;

    # $len is the length of the string that is currently being constructed.
    my $len = 0;

    # $rows is the number of rows to be occupied by the line.  This is always
    # at least one: a null line still occupies a row.
    my $rows = 1;

    # Keep an eye on the wrapchars (the prefix string to be output before
    # each wrapped line of text.)
    my $wrapchar = '';

    # Walk down the old format, processing each code in turn.
    while (@$fmt) {
	my $t = shift @$fmt;

	if ($t == $FOwrapchar) {
	    $wrapchar = shift @$fmt;
	    push @fmt, $t, $wrapchar;
	    next;
	} elsif ($t == $FOwrap) {
	    # We just ignore these -- they are the results of previous
	    # line_wrap operations.
	    next;
	} elsif ($t == $FOtext) {
	    $len += shift @$fmt;
	    next;
	}

	# If we have reached this point, we shall want to commit the text
	# (if any) we have currently pending.

	if ($len) {
	    while ($len + $x > $term->term_cols) {
		# The current chunk of text is too long!  We need to wrap it.

		# Locate the character at which we may break the line.
		my $tmp = rindex(substr($line, $idx, $term->term_cols - $x+1), ' ');

		if (($tmp == -1) || (($term->term_cols - $x - $tmp) > 10)) {
		    # There is no adequate breakpoint: we will just have to
		    # split a word.
		    $tmp = $term->term_cols - $x;
		} else {
		    $tmp++;
		}

		push @fmt, $FOtext, $tmp, $FOwrap;
		$x = length $wrapchar;
		$idx += $tmp;
		$len -= $tmp;
		$rows++;
	    }

	    # Whatever text remains will fit on the current row; commit it.
	    push @fmt, $FOtext, $len;
	    $idx += $len;
	    $x += $len;
	    $len = 0;
	}

	if ($t == $FOnewline) {
	    push @fmt, $FOnewline;
	    $x = 0;
	    $rows++;
	} elsif ($t == $FOattr) {
	    push @fmt, $FOattr, shift @$fmt;
	} elsif ($t == $FOpopattr) {
	    push @fmt, $FOpopattr;
	}
    }

    @$fmt = @fmt;
    return $rows;
}


# Returns the height of a line, in rows.  If necessary, line_wrap() is called
# on the line, and the result is stored in the @text_heights cache.
sub line_height($) {
    my($idx) = @_;
    if (!defined $text_heights[$idx]) {
	$text_heights[$idx] = line_wrap($text_lines[$idx], $text_fmts[$idx]);
    }
    return ($text_heights[$idx]);
}


# Determines if a given line should be shown or not.
sub win_showline($) {
    my($l) = @_;

    my $show = 1;
    my $tag;
    if (@text_show_tags) {
	$show = 0;
	foreach $tag (@text_show_tags) {
	    $show = 1 if (grep { $_ eq $tag } @{$text_tags[$l]});
	}
    }

    if (@text_hide_tags && $show) {
	foreach $tag (@text_hide_tags) {
	    $show = 0 if (grep { $_ eq $tag } @{$text_tags[$l]});
	}
    }

    return $show;
}


# Redraws the text window.
sub win_redraw() {
    my $y = win_height() - $text_r;
    my $l = $text_l;

    while (($l > 0) && (!win_showline($l))) {
	$l--;
    }

    while (($y > 0) && ($l > 0)) {
	win_draw_line($y, $text_lines[$l], $text_fmts[$l],
		      0, win_height() - $y + 1);

	$l--;
	while (($l > 0) && (!win_showline($l))) {
	    $l--;
	}

	$y -= line_height($l) if ($l > 0);
    }

    if (($l > 0) && (line_height($l) > -$y)) {
	win_draw_line(0, $text_lines[$l], $text_fmts[$l], 
		      -$y, win_height());
    } else {
	while (--$y > 0) {
	    $term->term_move($y, 0);
	    $term->term_delete_to_end();
	}
    }

    input_position_cursor();
}


# Scrolls the text window.
sub win_scroll($) {
    my($n) = @_;

    if ($n > 0) {
	my $i;
	for ($i = 0; $i < $n; $i++) {
	    $text_r++;
	    if ($text_r >= line_height($text_l)) {
		$text_r = 0;
		$text_l++;
		while (($text_l <= $#text_lines) && (!win_showline($text_l))) {
		    $text_l++;
		}
		last if ($text_l > $#text_lines);
	    }

	    $term->term_move(0,0);
	    $term->term_delete_line();
	    $term->term_move(win_height(),0);
	    $term->term_insert_line();

	    win_draw_line(win_height(),
			  $text_lines[$text_l], $text_fmts[$text_l],
			  $text_r, 1);
	}
    } elsif ($n < 0) {
	my $i;

	my($top_r, $top_l) = ($text_r, $text_l);
	for ($i = 0; $i < win_height(); $i++) {
	    $top_r--;
	    if ($top_r < 0) {
		$top_l--;
		while (($top_l >= 0) && (!win_showline($top_l))) {
		    $top_l--;
		}
		$top_r = ($top_l < 0) ? 0 : line_height($top_l) - 1;
	    }
	}

	for ($i = 0; $i > $n; $i--) {
	    $text_r--;
	    if ($text_r < 0) {
		$text_l--;
		while (($text_l >= 0) && (!win_showline($text_l))) {
		    $text_l--;
		}
		last if ($text_l < 0);
		$text_r = line_height($text_l) - 1;
	    }

	    $top_r--;
	    if ($top_r < 0) {
		$top_l--;
		while (($top_l >= 0) && (!win_showline($top_l))) {
		    $top_l--;
		}
		$top_r = ($top_l < 0) ? 0 : line_height($top_l) - 1;
	    }

	    $term->term_move(win_height(),0);
	    $term->term_delete_line();
	    $term->term_move(0,0);
	    $term->term_insert_line();

	    if ($top_l >= 0) {
		win_draw_line(0, $text_lines[$top_l], $text_fmts[$top_l],
			      $top_r, 1);
	    } else {
		$term->term_delete_to_end();
	    }
	}
    }

    if ($text_l < 0) {
	$text_l = 0;
	$text_r = 0;
    } elsif ($text_l > $#text_lines) {
	$text_l = $#text_lines;
	$text_r = line_height($text_l) - 1;
    }

    input_position_cursor();
}


# Adds a line of text to the text window.
sub ui_output {
    my %h;
    if (@_ == 1) {
	%h = (Text => $_[0]);
    } else {
	%h = @_;
    }

    my($line, $fmt);
    ($line, $fmt) = fmtline($h{Text});
    unshift @$fmt, $FOwrapchar, $h{WrapChar} if ($h{WrapChar});

    push @text_lines, $line;
    push @text_fmts, $fmt;
    $text_tags[$#text_lines] = [ @{$h{Tags}} ] if (defined $h{Tags});

    my $h = line_height($#text_lines);

    if ($scrolled_rows + $h >= win_height()) {
	$h = win_height() - $scrolled_rows - 1;
    }
    if (($h > 0) && ($text_l == $#text_lines - 1) &&
	($text_r == line_height($text_l) - 1)) {
      $scrolled_rows += $h  if ($config{pager});
	win_scroll($h);
    }

    scroll_info();
    $term->term_refresh();
}


# Returns the size (in lines) of the text window.
sub win_height() {
    return $term->term_lines - 2 - $input_height;
}


# Redraws the status line.
sub sline_redraw() {
    my $s;
    if ($page_status eq 'normal') {
	$s = $status_line;
    } else {
	my $t = time;
	return if ($t == $status_update_time);
	$status_update_time = $t;
	$s = $status_intern;
    }
    my $sline = "<status_line>" . $s . (' ' x $term->term_cols) . "</status_line>";
    my $sfmt;
    ($sline, $sfmt) = fmtline($sline);
    win_draw_line($term->term_lines-1-$input_height, $sline, $sfmt);
    input_position_cursor();
}


# Sets the status line.
sub ui_status($) {
    my ($s) = @_;
    $status_line = $s;
    sline_redraw();
    $term->term_refresh();
}


# Positions the input cursor.
sub input_position_cursor() {
    my $xpos = length($input_prompt);
    $xpos += $input_pos unless ($password);
    $term->term_move($term->term_lines - $input_height + int(($xpos / $ui_cols)) - $input_fline,
	      $xpos % $ui_cols);
}


# Redraws the input line.
sub input_redraw() {
    attr_use('input_line');

    my $l = $input_prompt;
    $l .= $input_line unless ($password);

    my $height = int((length($l) / $ui_cols)) + 1 - $input_fline;
    $height = 1 if ($height < 1);

    $term->term_move($term->term_lines - 1, 0);
    $term->term_delete_to_end();

    my $i;
    for ($i = 0; $i < length($l) / $ui_cols; $i += 1) {
	next if ($i < $input_fline);
	$term->term_move($term->term_lines - $height + $i, 0);
	$term->term_delete_to_end();
	$term->term_addstr(substr($l,$i*$ui_cols,$ui_cols));
    }

    if ($input_height != $height) {
	$input_height = $height;
	win_redraw();
	sline_redraw();
    }

    input_position_cursor();
    attr_top();
}


# Restores sanity to the input cursor.
sub input_normalize_cursor() {
    if ($input_pos > length $input_line) {
	$input_pos = length $input_line;
    } elsif ($input_pos < 0) {
	$input_pos = 0;
    }
}


# Inserts a character into the input line.
sub input_add($$$) {
    my($key, $line, $pos) = @_;
    $line = substr($line, 0, $pos) . $key . substr($line, $pos);

    return ($line, $pos + 1, 2) if ($password);

    my $l = $input_prompt . $line;
    if (length($l) % $term->term_cols == 0) {
	return ($line, $pos + 1, 2);
    }

    my $ii = $input_height - $input_fline - 1;
    my $i = $ii;
    while ($i * $term->term_cols > $pos) {
	$term->term_move($term->term_lines - $input_height + $i, 0);
	$term->term_insert_char();
	$term->term_addstr(substr($l, $i * $term->term_cols, 1));
	$i--;
    }
    input_position_cursor();
    $term->term_insert_char();
    $term->term_addstr($key);
    return ($line, $pos + 1, 0);
}


# Moves the input cursor left.
sub input_left($$$) {
    my($key, $line, $pos) = @_;
    return ($line, $pos - 1, 1);
}


# Moves the input cursor right.
sub input_right($$$) {
    my($key, $line, $pos) = @_;
    return ($line, $pos + 1, 1);
}


# Moves the input cursor to the beginning of the line.
sub input_home($$$) {
    my($key, $line, $pos) = @_;
    return ($line, 0, 1);
}


# Moves the input cursor to the end of the line.
sub input_end($$$) {
    my($key, $line, $pos) = @_;
    return ($line, length $line, 1);
}


# Deletes the character before the input cursor.
sub input_bs($$$) {
    my($key, $line, $pos) = @_;
    return if ($pos == 0);
    $line = substr($line, 0, $pos - 1) . substr($line, $pos);

    return ($line, $pos + 1, 2) if ($password);

    my $l = $input_prompt . $line;

    if (length($l) % $term->term_cols == 0) {
	return ($line, $pos - 1, 2);
    }

    my $ii = $input_height - $input_fline - 1;
    my $i = $ii;
    while ($i * $term->term_cols > $pos) {
	$term->term_move($term->term_lines - $input_height + $i, 0);
	$term->term_delete_char();
	$i--;
	$term->term_move($term->term_lines - $input_height + $i, $term->term_cols - 1);
	$term->term_addstr(substr($l, ($i * $term->term_cols) + $term->term_cols - 1, 1));
    }
    input_position_cursor();
    $term->term_delete_char();
    return ($line, $pos - 1, 2);
}


# Deletes the character after the input cursor.
sub input_del($$$) {
    my ($key, $line, $pos) = @_;
    return if ($pos >= length($line));
    return input_bs('', $line, $pos + 1);
}


# Yanks the kill bufffer back.
sub input_yank($$$) {
    my ($key, $line, $pos) = @_;
    $line = substr($line, 0, $pos) . $input_killbuf . substr($line, $pos);
    return ($line, $pos + length($input_killbuf), 2);
}


# Deletes the word preceding the input cursor.
sub input_killword($$$) {
    my ($key, $line, $pos) = @_;
    my $oldlen = length $line;
    substr($line, 0, $pos) =~ s/(\S+\s*)$//;
    $input_killbuf = $1;
    return ($line, $pos - ($oldlen - length($line)), 2);
}


# Deletes all characters to the end of the line.
sub input_killtoend($$$) {
    my($key, $line, $pos) = @_;
    $input_killbuf = substr($line, $pos);
    return (substr($line, 0, $pos), $pos, 2);
}


# Deletes all characters to the beginning of the line.
sub input_killtohome($$$) {
    my($key, $line, $pos) = @_;
    $input_killbuf = substr($line, 0, $pos);
    return (substr($line, $pos), 0, 2);
}


# Rotates the position of the previous two characters.
sub input_twiddle($$$) {
    my($key, $line, $pos) = @_;
    return if ($pos == 0);
    $pos++ if ($pos < length($line));
    my $tmp = substr($line, $pos-2, 1);
    substr($line, $pos-2, 1) = substr($line, $pos-1, 1);
    substr($line, $pos-1, 1) = $tmp;
    return ($line, $pos, 2);
}


# Moves back one entry in the history.
sub input_prevhistory($$$) {
    my($key, $line, $pos) = @_;
    return if ($input_curhistory <= 0);
    $input_history[$input_curhistory] = $line;
    $input_curhistory--;
    $line = $input_history[$input_curhistory];
    return ($line, length $line, 2);
}


# Moves forward one entry in the history.
sub input_nexthistory($$$) {
    my($key, $line, $pos) = @_;
    return if ($input_curhistory >= $#input_history);
    $input_history[$input_curhistory] = $line;
    $input_curhistory++;
    $line = $input_history[$input_curhistory];
    return ($line, length $line, 2);
}


# Handles entry of a new line.
sub input_accept($$$) {
    my($key, $line, $pos) = @_;

    return input_add(' ', $line, $pos) if ($input_pastemode);

    if (($line eq '') && (($text_l != $#text_lines) ||
			  ($text_r != line_height($text_l) - 1))) {
	input_pagedown();
	return ($line, $pos, 0);
    }

    $input_prompt = '';
    $input_curhistory = $#input_history;

    if (($line ne '') && (!$password)) {
	$input_history[$#input_history] = $line;
	push @input_history, '';
	$input_curhistory = $#input_history;
    }

    push @accepted_lines, $line;
    $input_fline = 0;
    return ('', 0, 2);
}


# Redraw the UI screen.
sub input_refresh($$$) {
    my($key, $line, $pos) = @_;
    redraw();
    return($line, $pos, 0);
}


# Toggles paste mode.
sub input_pastemode() {
    my($key, $line, $pos) = @_;
    my $paste_prompt = "Paste: ";
    if ($input_pastemode) {
	ui_prompt("") if ($input_prompt eq $paste_prompt);
	$input_pastemode = 0;
    } else {
	ui_prompt($paste_prompt) unless ($input_prompt);
	$input_pastemode = 1;
    }
    return($line, $pos, 0);
}


# Page up.
sub input_pageup($$$) {
    my($key, $line, $pos) = @_;
    &win_scroll(-win_height());
    scroll_info();
    $term->term_refresh();
    return($line, $pos, 0);
}


# Page down.
sub input_pagedown($$$) {
    my($key, $line, $pos) = @_;
    &win_scroll(win_height());
    scroll_info();
    $term->term_refresh();
    return($line, $pos, 0);
}


# To first line
sub input_scrollfirst($$$) {
    my($key, $line, $pos) = @_;
    $text_l = 0;
    $text_r = 0;

    my $rows = 1;
    while (($rows < $term->term_lines) && ($text_l <= $#text_lines)) {
	$rows++;
	$text_r++;
	if ($text_r >= line_height($text_l)) {
	    $text_l++;
	    $text_r = 0;
	}
    }
    if ($text_l > $#text_lines) {
	$text_l = $#text_lines;
	$text_r = line_height($text_l) - 1;
    }

    win_redraw();
    $term->term_refresh();
    return($line, $pos, 0);
}


# To last line
sub input_scrolllast($$$) {
    my($key, $line, $pos) = @_;
    $text_l = $#text_lines;
    $text_r = line_height($text_l) - 1;
    win_redraw();
    $term->term_refresh();
    return($line, $pos, 0);
}


# Redraws the UI screen.
sub redraw() {
    $term->term_clear();
    &win_redraw;
    &sline_redraw();
    &input_redraw;
    $term->term_refresh();
}


# Returns scrollback information.
sub scroll_info() {
    if (($text_l != $#text_lines) || ($text_r != line_height($text_l) - 1)) {
	my $lines = line_height($text_l) - $text_r - 1;
	my $i;
	for ($i = $text_l + 1; $i <= $#text_lines; $i++) {
	    $lines += line_height($i);
	}
	$page_status = 'more';
	$status_intern = "-- MORE ($lines) --";
	$status_intern = (' ' x int(($term->term_cols - length($status_intern)) / 2)) .
	    $status_intern;
	sline_redraw();
	$term->term_refresh();
    } else {
	$page_status = 'normal';
	sline_redraw();
	$term->term_refresh();
    }
}


# Registers an input callback function.
sub ui_callback($$) {
    my($key, $cb) = @_;
    push @{$key_trans{$key}}, $cb;
}


# Deregisters an input callback function.
sub ui_remove_callback($$) {
    my($key, $cb) = @_;
    @{$key_trans{$key}} = grep { $_ ne $cb } @{$key_trans{$key}};
}


# Accepts input from the terminal.
sub ui_process() {
    my $c;

    while (1) {
	$c = $term->term_get_char();
	last if ((!defined($c)) || ($c eq '-1'));

	$scrolled_rows = 0;
	$status_update_time = 0;

	attr_use('input_line');

	my @res;
	foreach (@{$key_trans{$c}}) {
	    @res = &$_($c, $input_line, $input_pos);
	    last if (@res);
	}
	if ((scalar(@res) == 0) && isprint($c) && length($c) == 1) {
	    @res = input_add($c, $input_line, $input_pos);
	}

	if (@res) {
	    my $update = 0;
	    ($input_line, $input_pos, $update) = @res;
	    input_normalize_cursor();
	    if ($update == 1) {
		input_position_cursor();
	    } elsif ($update == 2) {
		input_redraw();
		$term->term_refresh();
	    }
	}

	attr_top();
    }	

    scroll_info();
    return shift @accepted_lines;
}


# Rings the bell.
sub ui_bell() {
    $term->term_bell();
}


# Sets password (noecho) mode.
sub ui_password($) {
    $password = $_[0];
}


# Sets the prompt.
sub ui_prompt($) {
    $input_prompt = $_[0];
    input_redraw();
    $term->term_refresh();
}

sub ui_set(%) {
    my(%h) = @_;

    my $key;
    foreach $key (keys %h) {
	if ($key eq 'Show') {
	    @text_show_tags = @{$h{$key}};
	    win_redraw();
	    $term->term_refresh();
	} elsif ($key eq 'Hide') {
	    @text_hide_tags = @{$h{$key}};
	    win_redraw();
	    $term->term_refresh();
	}
    }
}


sub ui_select($$$$) {
    my($r, $w, $e, $t) = @_;
    return $term->term_select($r, $w, $e, $t);
}

1;

