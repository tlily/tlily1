# -*- Perl -*-
package LC::UI;

use Exporter;

use IO::Handle;
use POSIX;

use LC::config;
use LC::CTerminal;

use LC::log;

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
	     $ui_lines
	     $ui_cols);


my $ui_up = 0;

my $password = 0;

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

my $input_killbuf = "";

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
		 'C-b'  => [ \&input_pageup ],
		 'pgdn' => [ \&input_pagedown ],
		 'C-f'  => [ \&input_pagedown ],
		 'C-t'  => [ \&input_twiddle ],
		 'nl'   => [ \&input_accept ],
		 'C-y'  => [ \&input_yank ],
		 'C-w'  => [ \&input_killword ],
		 'C-l'  => [ \&input_refresh ],
		 'C-d'  => [ \&input_del ],
		 'C-h'  => [ \&input_bs ],
		 'bs'   => [ \&input_bs ]
		 );

my %attr_list = ();
my %attr_cmap = ();
my @attr_stack = ();
my $attr_cur_bg = COLOR_BLACK;
my $attr_cur_fg = COLOR_WHITE;


# Starts the curses UI.
sub ui_start () {
    term_init();
    $ui_lines = $term_lines;
    $ui_cols = $term_cols;
    &redraw;
}


# Terminates the UI.
sub ui_end () {
    term_end();
}


# Define a new attribute.
sub ui_attr ($@) {
    my ($name,@attrs) = @_;
    $attr_list{$name} = \@attrs;
}


# Selects an attribute for use.
sub attr_use ($) {
    my($name) = @_;

    my @curattrs = term_getattr();
    push @attr_stack, \@curattrs;

    return if (!defined $attr_list{$name});

    my $attrs = $attr_list{$name};
    term_setattr(@$attrs);
}


# Pops attribute usage stack.
sub attr_pop () {
    my $attrs = pop @attr_stack;
    term_setattr(@$attrs);
}


# Rolls out the attribute stack.
sub attr_top () {
    my $attrs;
    while (@attr_stack) {
	$attrs = pop @attr_stack;
    }
    term_setattr(@$attrs);
}


# Breaks a string into line-sized pieces.
sub fmtline ($) {
    my($text) = @_;

    my @lines = ();
    foreach $blk (split /\r?\n/, $text) {
	my $line = '';
	my $linelen = 0;
	my $word;
	$blk =~ s/\\\\//g;
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
		if ($linelen + length($&) > $term_cols) {
		    if ($linelen < $term_cols - 10) {
			$line .= substr($blk, 0, $term_cols - $linelen);
			$blk = substr($blk, $term_cols - $linelen);
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
	$line =~ tr//\\/;
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

    $text_sizes[$idx] = fmtline($text_lines[$idx])
	unless (defined $text_sizes[$idx]);
    return $text_sizes[$idx];
}


# Returns the size (in lines) of the text window.
sub win_height () {
    return $term_lines - 2 - $input_height;
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

    $line =~ s/\\\\//g;
    $line =~ s/\\\<//g;
    $line =~ s/\\(.)/$1/g;
    $line =~ tr/</<\\/;

    my $xpos = 0;

    attr_use('text_window');

    term_move($ypos, 0);
    term_delete_to_end();

    while ((length $line) && ($xpos < $term_cols)) {
	if ($line =~ /^\/([^\>]*)\>/) {
	    attr_pop();
	    $line = substr($line, length $&);
	} elsif ($line =~ /^([^\>]*)\>/) {
	    attr_use($1);
	    $line = substr($line, length $&);
	} elsif ($line =~ /^[^]+/) {
	    my $len = $term_cols - $xpos;
	    term_addstr(substr($&,0,$len));
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
    my $cline = win_height();
    my $idx = $win_endline;
    while ($cline >= 0) {
	my $s = win_index($idx--);
	win_draw_line($cline--, ($s ? $s : ""));
    }
    input_position_cursor();
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
	win_redraw();
	return;
    }

    if ($up) {
	my $i;
	for ($i = $n - 1; $i >= 0; $i--) {
	    term_move(0,0);
	    term_delete_line();
	    term_move(win_height(),0);
	    term_insert_line();
	    my $s = win_index($win_endline - $i);
	    win_draw_line(win_height(), ($s ? $s : ''));
	}
    } else {
	my $i;
	for ($i = 0; $i < $n; $i++) {
	    term_move(win_height(),0);
	    term_delete_line();
	    term_move(0,0);
	    term_insert_line();

	    my $s = win_index($win_endline - $i - 1);
	    win_draw_line(0, ($s ? $s : ''));
	}
    }

    input_position_cursor();
}


# Adds a line of text to the text window.
sub ui_output ($) {
    my($line) = @_;
    $line =~ s/[\r]//g;
    $line = ' ' if ($line eq '');
    push @text_lines, $line;
    my $atend = ($text_lastline == $win_endline) ? 1 : 0;
    my @fmt = fmtline($line);
    $text_lastline += scalar(@fmt);
    if ($atend) {
	my $max_scroll = win_height() - ($win_endline - $win_lastseen);
	if ($max_scroll > 0) {
	    win_scroll($max_scroll > scalar(@fmt) ?
		       scalar(@fmt) : $max_scroll);
	}
    }
    scroll_info();
    term_refresh();
}


# Redraws the status line.
sub sline_redraw () {
    my $s;
    if ($page_status eq 'normal') {
	$s = $status_line;
    } else {
	my $t = time;
	return if ($t == $status_update_time);
	$status_update_time = $t;
	$s = $status_intern;
    }
    my $sline = "<status_line>" . $s . (' ' x $term_cols) .
	"</status_line>";
    win_draw_line($term_lines-1-$input_height, $sline);
    input_position_cursor();
}


# Sets the status line.
sub ui_status ($) {
    my ($s) = @_;
    $status_line = $s;
    sline_redraw();
    term_refresh();
}


# Positions the input cursor.
sub input_position_cursor () {
    if ($password) {
	term_move($term_lines - $input_height, 0);
	return;
    }

    term_move($term_lines - $input_height + floor(($input_pos / 80)) - $input_fline,
	      $input_pos % 80);
}


# Redraws the input line.
sub input_redraw () {
    attr_use('input_line');

    my $height = floor((length($input_line) / 80)) + 1 - $input_fline;
    $height = 1 if ($height < 1);

    term_move($term_lines - 1, 0);
    term_delete_to_end();

    return if ($password);

    my($i, $line);
    for ($i = 0; $i < length($input_line) / 80; $i += 1) {
	next if ($i < $input_fline);
	term_move($term_lines - $height + $i, 0);
	term_delete_to_end();
	term_addstr(substr($input_line,$i*80,80));
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
sub input_normalize_cursor () {
    if ($input_pos > length $input_line) {
	$input_pos = length $input_line;
    } elsif ($input_pos < 0) {
	$input_pos = 0;
    }
}


# Inserts a character into the input line.
sub input_add ($$$) {
    my($key, $line, $pos) = @_;
    $line = substr($line, 0, $pos) . $key . substr($line, $pos);

    return ($line, $pos + 1, 2) if ($password);

    if (length($line) % $term_cols == 0) {
	return ($line, $pos + 1, 2);
    }

    my $ii = $input_height - $input_fline - 1;
    my $i = $ii;
    while ($i * $term_cols > $pos) {
	term_move($term_lines - $input_height + $i, 0);
	term_insert_char();
	term_addstr(substr($line, $i * $term_cols, 1));
	$i--;
    }
    input_position_cursor();
    term_insert_char();
    term_addstr($key);
    return ($line, $pos + 1, 0);
}


# Moves the input cursor left.
sub input_left ($$$) {
    my($key, $line, $pos) = @_;
    return ($line, $pos - 1, 1);
}


# Moves the input cursor right.
sub input_right ($$$) {
    my($key, $line, $pos) = @_;
    return ($line, $pos + 1, 1);
}


# Moves the input cursor to the beginning of the line.
sub input_home ($$$) {
    my($key, $line, $pos) = @_;
    return ($line, 0, 1);
}


# Moves the input cursor to the end of the line.
sub input_end ($$$) {
    my($key, $line, $pos) = @_;
    return ($line, length $line, 1);
}


# Deletes the character before the input cursor.
sub input_bs ($$$) {
    my($key, $line, $pos) = @_;
    return if ($pos == 0);
    $line = substr($line, 0, $pos - 1) . substr($line, $pos);

    return ($line, $pos + 1, 2) if ($password);

    if (length($line) % $term_cols == 0) {
	return ($line, $pos - 1, 2);
    }

    my $ii = $input_height - $input_fline - 1;
    my $i = $ii;
    while ($i * $term_cols > $pos) {
	term_move($term_lines - $input_height + $i, 0);
	term_delete_char();
	$i--;
	term_move($term_lines - $input_height + $i, $term_cols - 1);
	term_addstr(substr($line, ($i * $term_cols) + $term_cols - 1, 1));
    }
    input_position_cursor();
    term_delete_char();
    return ($line, $pos - 1, 2);
}


# Deletes the character after the input cursor.
sub input_del ($$$) {
    my ($key, $line, $pos) = @_;
    return if ($pos >= length($line));
    return input_bs('', $line, $pos + 1);
}


# Yanks the kill bufffer back.
sub input_yank ($$$) {
    my ($key, $line, $pos) = @_;
    $line = substr($line, 0, $pos) . $input_killbuf . substr($line, $pos);
    return ($line, $pos + length($input_killbuf), 2);
}


# Deletes the word preceding the input cursor.
sub input_killword ($$$) {
    my ($key, $line, $pos) = @_;
    my $oldlen = length $line;
    substr($line, 0, $pos) =~ s/(\S+\s*)$//;
    $input_killbuf = $1;
    return ($line, $pos - (length($line) - $oldlen), 2);
}


# Deletes all characters to the end of the line.
sub input_killtoend ($$$) {
    my($key, $line, $pos) = @_;
    $input_killbuf = substr($line, $pos);
    return (substr($line, 0, $pos), $pos, 2);
}


# Deletes all characters to the beginning of the line.
sub input_killtohome ($$$) {
    my($key, $line, $pos) = @_;
    $input_killbuf = substr($line, 0, $pos);
    return (substr($line, $pos), 0, 2);
}


# Rotates the position of the previous two characters.
sub input_twiddle ($$$) {
    my($key, $line, $pos) = @_;
    return if ($pos == 0);
    $pos++ if ($pos < length($line));
    my $tmp = substr($line, $pos-2, 1);
    substr($line, $pos-2, 1) = substr($line, $pos-1, 1);
    substr($line, $pos-1, 1) = $tmp;
    return ($line, $pos, 2);
}


# Moves back one entry in the history.
sub input_prevhistory ($$$) {
    my($key, $line, $pos) = @_;
    return if ($input_curhistory <= 0);
    $input_history[$input_curhistory] = $line;
    $input_curhistory--;
    $line = $input_history[$input_curhistory];
    return ($line, length $line, 2);
}


# Moves forward one entry in the history.
sub input_nexthistory ($$$) {
    my($key, $line, $pos) = @_;
    return if ($input_curhistory >= $#input_history);
    $input_history[$input_curhistory] = $line;
    $input_curhistory++;
    $line = $input_history[$input_curhistory];
    return ($line, length $line, 2);
}


# Handles entry of a new line.
sub input_accept ($$$) {
    my($key, $line, $pos) = @_;

    if (($line eq '') && ($text_lastline != $win_endline)) {
	input_pagedown();
	return ($line, $pos, 0);
    }

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
sub input_refresh ($$$) {
    my($key, $line, $pos) = @_;
    redraw();
    return($line, $pos, 0);
}


# Page up.
sub input_pageup ($$$) {
    my($key, $line, $pos) = @_;
    $win_lastseen = $win_endline if ($win_endline > $win_lastseen);
    &win_scroll(-win_height());
    scroll_info();
    term_refresh();
    return($line, $pos, 0);
}


# Page down.
sub input_pagedown ($$$) {
    my($key, $line, $pos) = @_;
    $win_lastseen = $win_endline if ($win_endline > $win_lastseen);
    &win_scroll(win_height());
    scroll_info();
    term_refresh();
    return($line, $pos, 0);
}


# Redraws the UI screen.
sub redraw () {
    term_clear();
    &win_redraw;
    &sline_redraw();
    &input_redraw;
    term_refresh();
}


# Returns scrollback information.
sub scroll_info () {
    if ($win_endline < $text_lastline) {
	my $lines = $text_lastline - $win_endline + 1;
	$page_status = 'more';
	$status_intern = "-- MORE ($lines) --";
	$status_intern = (' ' x int(($term_cols - length($status_intern)) / 2)) .
	    $status_intern;
	sline_redraw();
	term_refresh();
    } else {
	$page_status = 'normal';
	sline_redraw();
	term_refresh();
    }
}


# Registers an input callback function.
sub ui_callback ($$) {
    my($key, $cb) = @_;
    push @{$key_trans{$key}}, $cb;
}


# Deregisters an input callback function.
sub ui_remove_callback ($$) {
    my($key, $cb) = @_;
    @{$key_trans{$key}} = grep { $_ ne $cb } @{$key_trans{$key}};
}


# Accepts input from the terminal.
sub ui_process () {
    my $c;

    while (1) {
	$c = term_get_char();
	last if ((!defined($c)) || ($c eq '-1'));

	$status_update_time = 0;
	$win_lastseen = $win_endline if ($win_endline > $win_lastseen);
	scroll_info();

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
		term_refresh();
	    }
	}

	attr_top();
    }	

    return shift @accepted_lines;
}


# Rings the bell.
sub ui_bell () {
    term_bell();
}


# Sets password (noecho) mode.
sub ui_password ($) {
    $password = $_[0];
}

1;
