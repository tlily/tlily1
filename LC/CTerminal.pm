# -*- Perl -*-

package LC::CTerminal;

use Exporter;
use Curses;

@ISA = qw(Exporter);

@EXPORT = qw($term_lines
	     $term_cols
	     &term_init
	     &term_end
	     &term_clear
	     &term_getattr
	     &term_setattr
	     &term_addstr
	     &term_move
	     &term_delete_to_end
	     &term_insert_line
	     &term_delete_line
	     &term_insert_char
	     &term_delete_char
	     &term_get_char
	     &term_refresh);


my $term_up = 0;
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


# Initialize the terminal.
sub term_init () {
    return if ($term_up);
    initscr();
    $term_lines = $LINES; 
    $term_cols = $COLS;
    noecho();
    cbreak();
    keypad(1);
    nodelay(1);
    start_color();
    $term_up = 1;
}


# End use of the terminal.
sub term_end () {
    return unless ($term_up);
    endwin();
    %color_pairs = ('black:white' => 0);
    $term_up = 0;
}


# Gets the current attributes.
sub term_getattr () {
    my @a = ('normal');
    push @a, 'bold' if ($attrs{'bold'});
    push @a, 'reverse' if ($attrs{'reverse'});
    push @a, "fg:$attrs{foreground}";
    push @a, "bg:$attrs{background}";
    return @a;
}


# Sets some attributes.
sub term_setattr (@_) {
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
    clear;
}


# Writes text using the current style at the current position.
sub term_addstr ($) {
    addstr($_[0]);
}


# Repositions the cursor.
sub term_move ($$) {
    my ($y,$x) = @_;
    move($y,$x);
}


# Deletes all characters to the end of line.
sub term_delete_to_end () {
    clrtoeol();
}


# Inserts a new line at the current cursor position.
sub term_insert_line () {
    insertln();
}


# Deletes the line at the current cursor position.
sub term_delete_line () {
    deleteln();
}


# Inserts a character using the current style at the current cursor position.
sub term_insert_char () {
    insch(' ');
}


# Deletes the character at the current cursor position.
sub term_delete_char () {
    delch();
}

sub ALT_BACKSPACE () { return sprintf("%c",127); }

my %key_map = (&KEY_DOWN      => 'kd',
	       &KEY_UP        => 'ku',
	       &KEY_LEFT      => 'kl',
	       &KEY_RIGHT     => 'kr',
	       &KEY_PPAGE     => 'pgup',
	       &KEY_NPAGE     => 'pgdn',
	       &ALT_BACKSPACE => 'bs',     # fix for broken backspaces..
	       &KEY_BACKSPACE => 'bs');

# Returns a character if one is waiting, or undef otherwise.
sub term_get_char () {
    my $ch = getch;
    #return undef if ($ch eq ERR || $ch eq '-1');
    return undef if ($ch eq '-1');    
    return $key_map{$ch} || $ch;
}


# Redraws the screen.
sub term_refresh () {
    refresh();
}


1;
