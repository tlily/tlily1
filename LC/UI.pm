package LC::UI;

use Curses;
use POSIX;


my $ui_up = 0;

my @text_lines = ();
my $text_lastline = -1;

my $win_endline = -1;

my $input_line = "";
my $input_fchar = 0;
my $input_pos = 0;

my $status_line = "";

my @accepted_lines = ();

my %key_trans = (
		 (KEY_LEFT) => \&input_left,
		 (KEY_RIGHT) => \&input_right,
		 (KEY_HOME) => \&input_home,
		 '' => \&input_home,
		 (KEY_END) => \&input_end,
		 '' => \&input_end,
		 "\r" => \&input_accept,
		 "\n" => \&input_accept,
		 (KEY_BACKSPACE) => \&input_bs
		 );

my %attr_list = ();



# Starts the curses UI.
sub init () {
    initscr;
    cbreak; noecho; nodelay 1; keypad 1;
    &redraw;
    $ui_up = 1;
}


# Terminates the UI.
sub end () {
    return unless ($ui_up);
    clear;
    refresh;
    endwin;
    $ui_up = 0;
}


# Define a new attribute.
sub defattr ($@) {
    my $name = shift @_;
    foreach (@_) {
	push @{$attr_list{$name}}, $_;
    }
}


# Breaks a string into line-sized pieces.
sub fmtline ($$$) {
    my($itab,$stab,$text) = @_;
    my @blocks = split /\r?\n/, $text;
    my @lines = ();
    foreach $blk (@blocks) {
	$blk = $itab . $blk . ' ';
	my $cpos = 0;
	my $state = 0;
	my $line = '';
	my $linelen = 0;
	my $word = '';
	my $tag = '';
	my @tagstack = ();
	my $addspaces = 1;
	my $escape = 0;
	my $newline = 0;
	while ($cpos < length $blk) {
	    if ($newline) {
		$newline = 0;
		my $i;
		for ($i = $#tagstack; $i >= 0; $i--) {
		    $line .= "</$tagstack[$i]>";
		}
		push @lines, $line;
		$line = $stab;
		my $foo = $line;
		$foo =~ s/\<[^\>]*\>//g;
				$linelen = length $foo;
		foreach (@tagstack) {
		    $line .= "<$_>";
		}
	    }
	    my $char = substr($blk,$cpos,1);
	    #print "char='$char' state=$state word='$word'\n";
	    # Not in a word.
	    if ($state == 0) {
		if (isspace($char)) {
		    if ($addspaces) {
			if ($linelen < $COLS) {
			    $line .= ' ';
			    $linelen++;
			} else {
			    $newline = 1;
			    $addspaces = 0;
			}
		    }
		} elsif (($char eq '<') && ($escape == 0)) {
		    $state = 1;
		} elsif (($char eq '\\') && ($escape == 0)) {
		    $escape = 1;
		    $line .= $char;
		} else {
		    $addspaces = 1;
		    $word = $char;
		    $state = 2;
		}
		# Reading a tag.
	    } elsif ($state == 1) {
		if ($char eq '>') {
		    $line .= "<$tag>";
		    $state = 0;
		    if ($tag =~ /^\/(.*)$/) {
			if ($tagstack[$#tagstack] ne "$1") {
			    die "Tag nesting insanity!\n";
			}
			pop @tagstack;
		    } else {
			push @tagstack, $tag;
		    }
		    $tag = '';
		    if (length($word)) {
			$state = 2;
		    } else {
			$state = 0;
		    }
		} else {
		    $tag .= $char;
		}
		# Reading a word.
	    } elsif ($state == 2) {
		if (isspace($char) || (($char eq '<') && ($escape == 0))) {
		    if ($linelen + length($word) > $COLS) {
			if ($COLS - $linelen > 10) {
			    $line .= substr($word,0,$COLS - $linelen);
			    $word = substr($word, $COLS-$linelen);
			    $linelen = $COLS;
			}
			$newline = 1;
			redo;
		    } else {
			$line .= $word;
			$linelen += length($word);
			$word = '';
			$state = 0;
			redo;
		    }
		} elsif (($char eq '\\') && ($escape == 0)) {
		    $escape = 1;
		    $line .= $char;
		} else {
		    $word .= $char;
		}
	    }
	    
	    $cpos++;
	}
	
	if ($line !~ /^\s$/) {
	    push @lines, $line;
	}
    }
    if (@lines == 0) {
	push @lines, '';
    }
    return @lines;
}
 

my $win_idx_cline_idx;
my $win_idx_cline_num;
my @win_idx_ctext;

# Returns a given line (counting from the end) of text.
sub win_index ($) {
    my($num) = @_;

    return undef if (($num < 0) || ($num > $text_lastline));

    if (!defined $win_idx_cline_idx) {
	$win_idx_cline_idx = 0;
	$win_idx_cline_num = 0;
	@win_idx_ctext = fmtline('','',$text_lines[$win_idx_cline_idx]);
    }

    while ($num < $win_idx_cline_num) {
	$win_idx_cline_idx--;
	@win_idx_ctext = fmtline('','',$text_lines[$win_idx_cline_idx]);
	$win_idx_cline_num -= scalar(@win_idx_ctext);
    }

    while ($num >= $win_idx_cline_num + scalar(@win_idx_ctext)) {
	$win_idx_cline_num += scalar(@win_idx_ctext);
	$win_idx_cline_idx++;
	@win_idx_ctext = fmtline('','',$text_lines[$win_idx_cline_idx]);
    }

    if (($num >= $win_idx_cline_num) &&
	($num < $win_idx_cline_num + scalar(@win_idx_ctext))) {
	return $win_idx_ctext[$win_idx_cline_num - $num];
    }

    return undef;
}


# Paints one line in the text window.
sub win_draw_line ($$) {
    my($ypos, $line) = @_;
    my $str = sprintf "%-".$COLS.".".$COLS."s", "";
    addstr($ypos, 0, $str);
    my $p = 0;
    my $xpos = 0;
    my $tag = "";
    my $state = 0;
    my @attrstack = ();
    $str = "";
    while ($p < length($line)) {
	my $char = substr($line, $p, 1);
	if ($state == 0) {
	    if ($char eq '<') {
		addstr $ypos, $xpos, $str;
		$xpos += length $str;
		$str = '';
		$state = 1;
	    } else {
		$str .= $char;
	    }
	} elsif ($state == 1) {
	    if ($char eq '>') {
		if (substr($tag, 0, 1) eq '/') {
		    attrset (pop @attrstack);
		} else {
		    push @attrstack, getattrs;
		    if (defined($attr_list{$tag})) {
			foreach (@{$attr_list{$tag}}) {
			    attron $_;
			}
		    }
		}
		$tag = '';
		$state = 0;
	    } else {
		$tag .= $char;
	    }
	}
	$p++;
    }
    addstr($ypos, $xpos, $str);
}


# Redraws the text window.
sub win_redraw () {
    getyx($y, $x);
    my $cline = $LINES - 3;
    my $idx = $win_endline;
    while ($cline >= 0) {
	my $s = win_index($idx--);
	win_draw_line($cline--, ($s ? $s : ""));
    }
    move($y,$x);
}


# Adds a line of text to the text window.
sub addline ($) {
    my($line) = @_;
    $line =~ s/[\r\n]//g;
    push @text_lines, $line;
    $text_lastline += scalar(fmtline('','',$line));
    $win_endline = $text_lastline;
    win_redraw;
    sline_redraw();
    refresh;
}


# Redraws the status line.
sub sline_redraw () {
    getyx($y, $x);
    my $sline = sprintf "%-".$COLS.".".$COLS."s", $status_line;

    attron(A_REVERSE);
    addstr($LINES - 2, 0, $sline);
    attroff(A_REVERSE);
    move($y,$x);
}


# Sets the status line.
sub sline_set ($) {
    $status_line = shift @_;
    sline_redraw();
    refresh;
}


# Redraws the input line.
sub input_redraw () {
    my $line = substr $input_line, $input_fchar;
    $line = sprintf "%-".$COLS.".".$COLS."s", $line;
    addstr($LINES - 1, 0, $line);
    move($LINES - 1, $input_pos - $input_fchar);
}


# Restores sanity to the input cursor.
sub input_normalize_cursor () {
    if ($input_pos > length $input_line) {
	$input_pos = length $input_line;
    } elsif ($input_pos < 0) {
	$input_pos = 0;
    }
    if ($input_pos - $input_fchar < 0) {
	$input_fchar = $input_pos;
    } elsif ($input_pos - $input_fchar > $COLS - 1) {
	$input_fchar = $input_pos - $COLS + 1;
    }
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


# Handles entry of a new line.
sub input_accept (;$) {
    push @accepted_lines, $input_line;
    $input_line = "";
    $input_pos = 0;
    $input_fchar = 0;
    input_redraw; refresh;
}


# Redraws the UI screen.
sub redraw () {
    clear;
    &win_redraw;
    &sline_redraw;
    &input_redraw;
    refresh;
}


# Accepts input from the terminal.
sub handle_input () {
    my $c;
    while ($c = getch) {
	last if ((!defined($c)) || ($c eq '-1'));

	if (defined $key_trans{$c}) {
	    &{$key_trans{$c}}($c);
	} elsif (isprint($c) && length($c) == 1) {
	    input_add $c;
	}
    }	
    return shift @accepted_lines;
}

1;
