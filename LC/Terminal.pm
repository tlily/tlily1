# -*- Perl -*-
# $Header: /data/cvs/tlily/LC/Terminal.pm,v 2.1 1998/06/12 08:56:19 albert Exp $

package LC::Terminal;

use Exporter;
use Term::Screen;
use Term::ANSIColor;

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
my $scr = undef;
my %attrs = ('bold' => 0,
	     'reverse' => 0,
	     'foreground' => 'black',
	     'background' => 'white');
my %colors = ('black', 1,
	      'red', 1,
	      'green', 1,
	      'yellow', 1,
	      'blue', 1,
	      'magenta', 1,
	      'cyan', 1,
	      'white', 1);


# Initialize the terminal.
sub term_init () {
    return if ($term_up);
    $scr = new Term::Screen;
    $term_lines = $scr->{ROWS};
    $term_cols = $scr->{COLS};
    $scr->noecho();
    $term_up = 1;
}


# End use of the terminal.
sub term_end () {
    return unless ($term_up);
    print color 'reset';
    $scr->echo();
    $scr = undef;
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
    foreach (@_) {
	if ($_ eq 'bold') {
	    next if ($attrs{'bold'});
	    $scr->bold();
	    $attrs{'bold'} = 1;
	} elsif ($_ eq 'reverse') {
	    next if ($attrs{'reverse'});
	    $scr->reverse();
	    $attrs{'reverse'} = 1;
	} elsif ($_ eq 'normal') {
	    next unless ($attrs{'bold'} || $attrs{'reverse'});
	    $scr->normal();
	    $attrs{'bold'} = 0;
	    $attrs{'reverse'} = 0;
	    print color $attrs{'foreground'};
	    print color 'on_'.$attrs{'background'};
	} elsif (/fg:(.*)/) {
	    my $c = $1;
	    if (!defined $colors{$c}) {
		warn "Foreground color $c is unknown\n";
		next;
	    }
	    next if ($attrs{'foreground'} eq $c);
	    print color $c;
	    $attrs{'foreground'} = $c;
	} elsif (/bg:(.*)/) {
	    my $c = $1;
	    if (!defined $colors{$c}) {
		warn "Background color $c is unknown\n";
		next;
	    }
	    next unless (defined $colors{$c});
	    next if ($attrs{'background'} eq $c);
	    print color 'on_'.$c;
	    $attrs{'background'} = $c;
	}
    }
}


# Clears the screen.
sub term_clear () {
    $scr->clrscr();
}


# Writes text using the current style at the current position.
sub term_addstr ($) {
    $scr->puts($_[0]);
}


# Repositions the cursor.
sub term_move ($$) {
    my ($y, $x) = @_;
    $scr->at($y,$x);
}


# Deletes all characters to the end of line.
sub term_delete_to_end () {
    $scr->clreol();
}


# Inserts a new line at the current cursor position.
sub term_insert_line () {
    $scr->il();
}


# Deletes the line at the current cursor position.
sub term_delete_line () {
    $scr->dl();
}


# Inserts a character using the current style at the current cursor position.
sub term_insert_char () {
    $scr->ic();
}


# Deletes the character at the current cursor position.
sub term_delete_char () {
    $scr->dc();
}


# Returns a character if one is waiting, or undef otherwise.
sub term_get_char () {
    return undef unless ($scr->key_pressed());
    return $scr->getch();
}


# Redraws the screen.
sub term_refresh () {
}


1;
