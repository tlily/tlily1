# -*- Perl -*-
# $Header: /data/cvs/tlily/LC/NoTerminal.pm,v 2.1 1998/06/12 08:56:11 albert Exp $

# Provides a Terminal module that does not depend on Curses or TermCap.  It's
# just simple stdio stuff.

# This is a huge hack.  The intention of this module was to provide a simple 
# terminal module to use when debugging tlily, including its UI module.
# The correct way to do this would have been to write a replacement UI.pm,
# rather than doing this as a terminal.

# This module has a number of problems, especially with drawing prompts and 
# such.  It's not going to look too good as a general-purpose UI, but it should
# be good 'nuff for debugging.  It should allow tlily to run inside perl -d, 
# I hope.

# It should also be good as a minimal UI to use while porting things to other
# platforms.

# Josh Wilmes

package LC::NoTerminal;

use IO::Select;
use POSIX;

use LC::Config;

sub new {
    bless {};
}


sub term_lines () { 24; }
sub term_cols () { 80; }


# Initialize the terminal.
sub term_init {
    select(STDOUT);
    system("stty -icanon -echo");
    $|=1;
}


# End use of the terminal.
sub term_end {
    system("stty sane");
}


# Gets the current attributes.
sub term_getattr () {
    my $self = shift;
    my @a = ('normal');
    return @a;
}


# Sets some attributes.
sub term_setattr (@_) {

}


# Clears the screen.
sub term_clear () {
    #system("clear");
}


# Writes text using the current style at the current position.
sub term_addstr ($) {
    my ($self,$str) = @_;
    
    print "$str" unless $noprint;
}


# Repositions the cursor.
sub term_move ($$) {
    my($self,$y,$x) = @_;
    if ($y == 22) { $noprint=1; } else { $noprint=0; }
}


# Deletes all characters to the end of line.
sub term_delete_to_end () {

}


# Inserts a new line at the current cursor position.
sub term_insert_line () {
    my ($self,$str) = @_;
    print "$str\n" unless $noprint;
}


# Deletes the line at the current cursor position.
sub term_delete_line () {

}


# Inserts a character using the current style at the current cursor position.
sub term_insert_char () {
    my ($self,$str) = @_;
    print "$str";
}


# Deletes the character at the current cursor position.
sub term_delete_char () {

}


# Rings the terminal bell
sub term_bell () {
    print "";
}

# Returns a character if one is waiting, or undef otherwise.
my $cbuf = '';
my $metaflag = 0;
my $ctrlflag = 0;
sub term_get_char () {
    my $self = shift;

    my $s = new IO::Select;
    $s->add(\*STDIN);
    return undef unless $s->can_read(0);

    sysread(STDIN, $cbuf, 1024, length $cbuf);
    my $c = substr($cbuf, 0, 1);
    $cbuf = substr($cbuf, 1);

    if (ord($c) == 27) {
	$metaflag = !$metaflag;
	return term_get_char();
    }

    if ((ord($c) >= 128) && (ord($c) < 256)) {
	$c = chr(ord($c) - 128);
	$metaflag = 1;
    }

    if ($c =~ /[\n\r]/) {
	$c = 'nl';
    }

    if (iscntrl($c)) {
	$c = chr(ord($c) + ord('a') - 1);
	$ctrlflag = 1;
    }

    my $res = (($metaflag ? "M-" : "") . ($ctrlflag ? "C-" : "") . $c);

    $metaflag = 0;
    $ctrlflag = 0;
 
    return $res;
}


# Redraws the screen.
sub term_refresh () {
#    print "term_refresh\n";
}


sub term_select ($$$$) {
    shift;
    my($rr, $wr, $er, $to) = @_;
 
    my $r = IO::Select->new(@$rr);
    my $w = IO::Select->new(@$wr);
    my $e = IO::Select->new(@$er);
    my @ret = IO::Select->select($r, $w, $e, $to);

    return @ret;
}


1;

