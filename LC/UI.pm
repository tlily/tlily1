# -*- Perl -*-
package LC::UI;

use Curses;
use IO::Handle;
use POSIX;


my $ui_up = 0;

my @text_lines = ();
my @text_sizes = ();
my $text_lastline = -1;

my $win_endline = -1;
my $win_lastseen = -1;

my $win_moremode = 0;

my $input_line = "";
my $input_height = 1;
my $input_fline = 0;
my $input_pos = 0;

my @input_history = ('');
my $input_curhistory = 0;

my $status_line = "";

my @accepted_lines = ();

my %key_trans = (
		 (KEY_LEFT) => \&input_left,
		 '' => \&input_left,
		 (KEY_RIGHT) => \&input_right,
		 '' => \&input_right,
		 (KEY_UP) => \&input_prevhistory,
		 '' => \&input_prevhistory,
		 (KEY_DOWN) => \&input_nexthistory,
		 '' => \&input_nexthistory,
		 (KEY_HOME) => \&input_home,
		 '' => \&input_home,
		 (KEY_END) => \&input_end,
		 '' => \&input_end,
		 '' => \&input_killtoend,
		 '' => \&input_killtohome,
		 (KEY_PPAGE) => \&input_pageup,
		 '' => \&input_pageup,
		 (KEY_NPAGE) => \&input_pagedown,
		 '' => \&input_pagedown,
		 "\r" => \&input_accept,
		 "\n" => \&input_accept,
		 "" => \&input_refresh,
		 (KEY_BACKSPACE) => \&input_bs
		 );

my %attr_list = ();
my %attr_cmap = ();
my @attr_stack = ();
my $attr_cur_bg = COLOR_BLACK;
my $attr_cur_fg = COLOR_WHITE;



# Starts the curses UI.
sub init () {
    initscr;
    start_color;
    cbreak; noecho; nodelay 1; keypad 1;
    $ui_up = 1;
    attr_define('status_line', COLOR_YELLOW, COLOR_BLUE, A_BOLD);
    attr_define('input_line', COLOR_WHITE, COLOR_BLACK, A_BOLD);
    attr_define('text_window', COLOR_WHITE, COLOR_BLACK, A_NORMAL);
    &redraw;
}


# Terminates the UI.
sub end () {
    return unless ($ui_up);
    clear;
    refresh;
    endwin;
    $ui_up = 0;
}


# Allocate a color.
sub color_alloc ($$) {
    my($fg,$bg) = @_;
    $id = "${fg}:${bg}";
    my $n = $attr_cmap{$id};
    if (!defined $n) {
	$n = scalar(keys %attr_cmap) + 1;
	init_pair $n, $fg, $bg;
	$attr_cmap{$id} = $n;
    }
    return $n;
}


# Use a given color pair.
sub attr_colors ($$$) {
    my($fg,$bg,$attr) = @_;

    attrset $attr;

    $fg = $attr_cur_fg if (!defined $fg);
    $bg = $attr_cur_bg if (!defined $bg);

    my $n = color_alloc($fg,$bg);

    $attr_cur_fg = $fg;
    $attr_cur_bg = $bg;

    attrset $attr | COLOR_PAIR($n);
}


# Define a new attribute.
sub attr_define ($$$$) {
    my ($name,$fg,$bg,$attrs) = @_;
    $attr_list{$name} = [$fg,$bg,$attrs];
}


# Selects an attribute for use.
sub attr_use ($) {
    my($name) = @_;

    push @attr_stack, [$attr_cur_fg, $attr_cur_bg, getattrs];

    return if (!defined $attr_list{$name});

    my $attrs = $attr_list{$name};
    attr_colors($$attrs[0], $$attrs[1], $$attrs[2]);
}


# Pops attribute usage stack.
sub attr_pop () {
    my $attrs = pop @attr_stack;
    attr_colors($$attrs[0], $$attrs[1], $$attrs[2]);
}


# Rolls out the attribute stack.
sub attr_top () {
    my $attrs;
    while (@attr_stack) {
	$attrs = pop @attr_stack;
    }
    attr_colors($$attrs[0], $$attrs[1], $$attrs[2]);
}


# Breaks a string into line-sized pieces.
sub fmtline ($) {
    my($text) = @_;

    my @lines = ();
    foreach $blk (split /\r?\n/, $text) {
	my $line = '';
	my $linelen = 0;
	my $word;
	$blk =~ s/\\\<//g;
	$blk =~ tr/</</;
	$blk =~ s/\\(.)/$1/g;
	@tagstack = ();
	while (length $blk) {
	    if ($blk =~ /^ +/) {
		$line .= $&;
		$linelen += length $&;
		$blk = substr($blk, length $&);
	    } elsif ($blk =~ /^\/([^\>]*)\>/) {
		$line .= $&;
		$blk = substr($blk, length $&);
		pop @tagstack;
	    } elsif ($blk =~ /^([^\>]*)\>/) {
		$line .= $&;
		$blk = substr($blk, length $&);
		push @tagstack, $1;
	    } elsif ($blk =~ /^[^ ]+/) {
		if ($linelen + length($&) > $COLS) {
		    if ($linelen < $COLS - 10) {
			$line .= substr($blk, 0, $COLS - $linelen);
			$blk = substr($blk, $COLS - $linelen);
		    }
		    foreach (reverse @tagstack) {
			$line .= "/$_>";
		    }
		    $line =~ s/([\<\\])/\\$1/g;
		    $line =~ tr//</;
		    push @lines, $line;
		    $line = '';
		    $linelen = 0;
		    foreach (@tagstack) {
			$line .= "$_>";
		    }
		} else {
		    $line .= $&;
		    $linelen += length $&;
		    $blk = substr($blk, length $&);
		}
	    } else {
		# This should never happen.
		$blk = substr($blk, 1);
	    }
		}
	foreach (reverse @tagstack) {
	    $line .= "/$_>";
	}
	$line =~ s/([\<\\])/\\$1/g;
	$line =~ tr//</;
	push @lines, $line if (length $line);
    }
    
    return @lines;
}
 

my $win_idx_cline_idx;
my $win_idx_cline_num;
my @win_idx_ctext;


# Returns the number of lines in a block of text.
sub linelen ($) {
    my ($idx) = @_;

    #addstr 2, 10, "==> $idx"; refresh; sleep 1;
    $text_sizes[$idx] = fmtline($text_lines[$idx])
	unless (defined $text_sizes[$idx]);
    return $text_sizes[$idx];
}


# Returns the size (in lines) of the text window.
sub win_height () {
    return $LINES - 2 - $input_height;
}


# Returns a given line (counting from the end) of text.
sub win_index ($) {
    my($num) = @_;

    return undef if (($num < 0) || ($num > $text_lastline));

    my $old_idx = $win_idx_cline_idx;

    if (!defined $win_idx_cline_idx) {
	$win_idx_cline_idx = 0;
	$win_idx_cline_num = 0;
    }

    while ($num < $win_idx_cline_num) {
	$win_idx_cline_idx--;
	$win_idx_cline_num -= linelen($win_idx_cline_idx);
    }

    while ($num >= $win_idx_cline_num + linelen($win_idx_cline_idx)) {
	$win_idx_cline_num += linelen($win_idx_cline_idx);
	$win_idx_cline_idx++;
    }

    if (!defined($old_idx) || ($old_idx != $win_idx_cline_idx)) {
	@win_idx_ctext = fmtline($text_lines[$win_idx_cline_idx]);
    }

    if (($num >= $win_idx_cline_num) &&
	($num < $win_idx_cline_num + scalar(@win_idx_ctext))) {
	return $win_idx_ctext[$num - $win_idx_cline_num];
    }

    return undef;
}


# Paints one line in the text window.
sub win_draw_line ($$) {
    my($ypos,$line) = @_;

    $line = ' ' if ($line eq '');

    $line =~ s/\\\<//g;
    $line =~ tr/</</;
    $line =~ s/\\(.)/$1/g;

    my $xpos = 0;

    attr_use('text_window');

    while ((length $line) && ($xpos < $COLS)) {
	if ($line =~ /^\/([^\>]*)\>/) {
	    attr_pop();
	    $line = substr($line, length $&);
	} elsif ($line =~ /^([^\>]*)\>/) {
	    attr_use($1);
	    $line = substr($line, length $&);
	} elsif ($line =~ /^[^]+/) {
	    my $len = $COLS - $xpos;
	    addstr $ypos, $xpos, sprintf "%-${len}.${len}s", $&;
	    $line = substr($line, length $&);
	    $xpos += length $&;
	} else {
	    # This should never happen.
	    $line = substr($line, 1);
	}
    }

    attr_top();
}


# Redraws the text window.
sub win_redraw () {
    getyx($y, $x);
    my $cline = win_height();
    my $idx = $win_endline;
    while ($cline >= 0) {
	my $s = win_index($idx--);
	win_draw_line($cline--, ($s ? $s : ""));
    }
    move($y,$x);
}


# Scrolls the text window.
sub win_scroll ($) {
    my($n) = @_;

    my $new_end = $win_endline + $n;
    $new_end = 0 if ($new_end < 0);
    $new_end = $text_lastline if ($new_end > $text_lastline);
    $n = $new_end - $win_endline;
    $win_endline = $new_end;

    my $up = ($n > 0) ? 1 : 0;
    $n = -$n if ($n < 0);

    if ($n > win_height()) {
	win_redraw;
	return;
    }

    getyx($y,$x);

    if ($up) {
	my $pad = newpad $LINES, $COLS;
	copywin stdscr, $pad, $n, 0, 0, 0, win_height() - $n, $COLS - 1, 0;
	copywin $pad, stdscr, 0, 0, 0, 0, win_height() - $n, $COLS - 1, 0;
	delwin $pad;

	my $i;
	for ($i = 0; $i < $n; $i++) {
	    my $s = win_index($win_endline - $i);
	    win_draw_line(win_height() - $i, ($s ? $s : ''));
	}
    } else {
	my $pad = newpad $LINES, $COLS;
	copywin stdscr, $pad, 0, 0, 0, 0, win_height() - $n, $COLS - 1, 0;
	copywin $pad, stdscr, 0, 0, $n, 0, win_height(), $COLS - 1, 0;
	delwin $pad;

	my $i;
	for ($i = 0; $i < $n; $i++) {
	    my $s = win_index($win_endline - (win_height()) + $i);
	    win_draw_line($i, ($s ? $s : ''));
	}
    }

    move($y,$x);
}


# Adds a line of text to the text window.
sub addline ($) {
    my($line) = @_;
    $line =~ s/[\r]//g;
    $line = ' ' if ($line eq '');
    push @text_lines, $line;
    my $atend = ($text_lastline == $win_endline) ? 1 : 0;
    my @fmt = fmtline($line);
    push(@fmt, '---') if (@fmt == 0);
    $text_lastline += scalar(@fmt);
    if ($atend) {
	my $max_scroll = win_height() - ($win_endline - $win_lastseen);
	if ($max_scroll > 0) {
	    win_scroll($max_scroll > scalar(@fmt) ?
		       scalar(@fmt) : $max_scroll);
	}
    }
    scroll_info();
    refresh;
}


# Redraws the status line.
sub sline_redraw () {
    getyx($y, $x);
    my $sline = "<status_line>${status_line}</status_line>";
    win_draw_line($LINES-1-$input_height, $sline);
    move($y, $x);
}


# Sets the status line.
sub sline_set ($) {
    $status_line = shift @_;
    sline_redraw();
    refresh;
}


# Redraws the input line.
sub input_redraw () {
    attr_use('input_line');

    my $height = floor((length($input_line) / 80)) + 1 - $input_fline;
    $height = 1 if ($height < 1);

    addstr $LINES - 1, 0, sprintf "%-".$COLS."s", '';

    my($i, $line);
    for ($i = 0; $i < length($input_line) / 80; $i += 1) {
	next if ($i < $input_fline);
	$line = sprintf "%-".$COLS.".".$COLS."s", substr($input_line,$i*80,80);
	addstr $LINES - $height + $i, 0, $line;
    }

    if ($input_height != $height) {
	$input_height = $height;
	win_redraw();
	sline_redraw();
    }

    move($LINES - $height + floor(($input_pos / 80)) - $input_fline,
	 $input_pos % 80);

    attr_top();
}


# Restores sanity to the input cursor.
sub input_normalize_cursor () {
#    if ($input_pos > length $input_line) {
#	$input_pos = length $input_line;
#    } elsif ($input_pos < 0) {
#	$input_pos = 0;
#    }
#
#    my $ypos = ($input_pos / 80) - $input_fline;
#    my $xpos = $input_pos % 80;
#
#    if ($ypos < 0) {
#	$fline += $ypos;
#	$ypos = 0;
#    }
#
#    if ($ypos >= $input_height) {
#	$fline += ($input_height - $ypos + 1);
#	$ypos = $input_height;
#    }
}


# Inserts a character into the input line.
sub input_add ($) {
    $input_line = substr($input_line, 0, $input_pos) .
	          shift(@_) .
	          substr($input_line, $input_pos);
    $input_pos++;
    &input_normalize_cursor;

    &input_redraw; refresh;
}


# Moves the input cursor left.
sub input_left (;$) {
    $input_pos-- unless ($input_pos <= 0);
    &input_normalize_cursor;
    &input_redraw; refresh;
}


# Moves the input cursor right.
sub input_right (;$) {
    $input_pos++ unless ($input_pos >= length $input_line);
    &input_normalize_cursor;
    &input_redraw; refresh;
}


# Moves the input cursor to the beginning of the line.
sub input_home (;$) {
    $input_pos = 0;
    &input_normalize_cursor;
    &input_redraw; refresh;
}


# Moves the input cursor to the end of the line.
sub input_end (;$) {
    $input_pos = length $input_line;
    &input_normalize_cursor;
    &input_redraw; refresh;
}


# Deletes the character before the input cursor.
sub input_bs (;$) {
    return if ($input_pos == 0);
    $input_line = substr($input_line, 0, $input_pos - 1) .
	          substr($input_line, $input_pos);
    $input_pos--;
    &input_normalize_cursor;
    &input_redraw; refresh;
}


# Deletes all characters to the end of the line.
sub input_killtoend (;$) {
    $input_line = substr($input_line, 0, $input_pos);
    input_redraw; refresh;
}


# Deletes all characters to the beginning of the line.
sub input_killtohome (;$) {
    $input_line = substr($input_line, $input_pos);
    $input_pos = 0;
    input_redraw; refresh;
}


# Moves back one entry in the history.
sub input_prevhistory (;$) {
    return if ($input_curhistory <= 0);
    $input_history[$input_curhistory] = $input_line;
    $input_curhistory--;
    $input_line = $input_history[$input_curhistory];
    $input_pos = length $input_line;
    input_redraw; refresh;
}


# Moves forward one entry in the history.
sub input_nexthistory (;$) {
    return if ($input_curhistory >= $#input_history);
    $input_history[$input_curhistory] = $input_line;
    $input_curhistory++;
    $input_line = $input_history[$input_curhistory];
    $input_pos = length $input_line;
    input_redraw; refresh;
}


# Handles entry of a new line.
sub input_accept (;$) {
    if (($input_line eq '') && ($text_lastline != $win_endline)) {
	input_pagedown();
	return;
    }

    if ($input_line ne '') {
	$input_history[$#input_history] = $input_line;
	push @input_history, '';
	$input_curhistory = $#input_history;
    }

    push @accepted_lines, $input_line;
    $input_line = "";
    $input_pos = 0;
    $input_fline = 0;
    input_redraw; refresh;
}


# Redraw the UI screen.
sub input_refresh (;$) {
    redraw();
}


# Page up.
sub input_pageup (;$) {
    $win_lastseen = $win_endline if ($win_endline > $win_lastseen);
    &win_scroll(-win_height());
    scroll_info();
    refresh;
}


# Page down.
sub input_pagedown (;$) {
    $win_lastseen = $win_endline if ($win_endline > $win_lastseen);
    &win_scroll(win_height());
    scroll_info();
    refresh;
}


# Redraws the UI screen.
sub redraw () {
    clear;
    &win_redraw;
    &sline_redraw;
    &input_redraw;
    refresh;
}


# Returns scrollback information.
sub scroll_info () {
    if (($win_endline - $win_lastseen) >= $LINES - 3) {
	my $lines = $text_lastline - $win_endline + 1;
	return if (($main::page_status ne '') && ($lines % 10));
	$main::page_status = "MORE " . $lines;
    } else {
	$main::page_status = '';
    }
}


# Accepts input from the terminal.
sub handle_input () {
    my $c;
    while ($c = getch) {
	last if ((!defined($c)) || ($c eq '-1'));

	$win_lastseen = $win_endline if ($win_endline > $win_lastseen);
	scroll_info();

	if (defined $key_trans{$c}) {
	    &{$key_trans{$c}}($c);
	} elsif (isprint($c) && length($c) == 1) {
	    input_add $c;
	}
    }	
    return shift @accepted_lines;
}

1;
