# -*- Perl -*-
package LC::TTerminal;

use IO::Select;
use Term::Cap;
use POSIX;

use LC::Config;

require 'termio.ph';

my %attrs = ('bold' => 0,
             'reverse' => 0);

my $term_up = 0;
my $resize_cb;

$term_resize_flag = 0;

my $term;
my $out = '';

my $save_c_lflag;
my $save_vmin;
my $save_vtime;


sub new {
    bless {};
}


sub term_resize_flag () { $term_resize_flag; }
sub term_lines () { $term_lines; }
sub term_cols () { $term_cols; }


# Determine the terminal size.
sub term_get_size () {
    my $winsize = '';
    #my $TIOCGWINSZ = (ord('T') << 8) | 104;
    if (ioctl(STDIN, &TIOCGWINSZ, $winsize)) {
	my($ws_row, $ws_col, $ws_xp, $ws_yp) = unpack("SSSS", $winsize);
	$ws_row = 24 if ($ws_row <= 0);
	$ws_col = 80 if ($ws_col <= 0);
	($LINES, $COLS) = ($ws_row, $ws_col);
	($ENV{LINES}, $ENV{COLUMNS}) = ($ws_row, $ws_col);
	return($ws_row, $ws_col);
    }
    return($LINES, $COLS);
}

# Initialize the terminal.
sub term_init ($) {
    my $self = shift;
    return if ($term_up);
    $resize_cb = $_[0];
    ($term_lines, $term_cols) = term_get_size;

    my $termios = new POSIX::Termios;
    $termios->getattr;
    my $ospeed = $termios->getospeed;

    $save_c_lflag = $termios->getlflag;
    $save_vmin    = $termios->getcc(&POSIX::VMIN);
    $save_vtime   = $termios->getcc(&POSIX::VTIME);

    my $c_lflag = $termios->getlflag;
    $c_lflag &= ~ICANON;
    $c_lflag &= ~ECHO;
    $termios->setlflag($c_lflag);

    $termios->setcc(&POSIX::VMIN, 1);
    $termios->setcc(&POSIX::VTIME, 0);

    $termios->setattr(0, &POSIX::TCSANOW);

    $term = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
    $term->Trequire(qw/cm/);

    my $term_flags = 0;
    fcntl(STDIN,F_GETFL,$term_flags) or die("fcntl: $!\n");
    $term_flags |= O_NONBLOCK;
    fcntl(STDIN,F_SETFL,$term_flags) or die("fcntl: $!\n");

    $| = 1;

    $config{mono} = 1;

    $SIG{WINCH} = sub { $term_resize_flag = 1; };

    term_clear();
    term_refresh();

    $term_up = 1;
}


# End use of the terminal.
sub term_end () {
    my $self = shift;
    return unless ($term_up);
    delete $SIG{WINCH};

    my $term_flags = 0;
    fcntl(STDIN,F_GETFL,$term_flags) or die("fcntl: $!\n");
    $term_flags &= ~O_NONBLOCK;
    fcntl(STDIN,F_SETFL,$term_flags) or die("fcntl: $!\n");

    my $termios = new POSIX::Termios;
    $termios->getattr;
    $termios->setlflag($save_c_lflag);
    $termios->setcc(&POSIX::VMIN, $save_vmin);
    $termios->setcc(&POSIX::VTIME, $save_vtime);
    $termios->setattr(0, &POSIX::TCSANOW);

    $term_up = 0;
}


# Handle a window size change.
sub term_winch () {
    my $self = shift;
    $term_resize_flag = 0;
    ($term_lines, $term_cols) = term_get_size;
    &$resize_cb if (defined $resize_cb);
}


# Gets the current attributes.
sub term_getattr () {
    my $self = shift;
    my @a = ('normal');
    push @a, 'bold' if ($attrs{'bold'});
    push @a, 'reverse' if ($attrs{'reverse'});
    return @a;
}


# Sets some attributes.
sub term_setattr (@_) {
    my $self = shift;
    my $attr;
    foreach $attr (@_) {
	if ($attr eq 'bold') {
	    next if ($attrs{'bold'});
	    $attrs{'bold'} = 1;
	    $out .= $term->Tputs('md', 1);
	} elsif ($attr eq 'reverse') {
	    next if ($attrs{'reverse'});
	    $attrs{'reverse'} = 1;
	    $out .= $term->Tputs('mr', 1);
	} elsif ($attr eq 'normal') {
	    next unless ($attrs{'bold'} || $attrs{'reverse'});
	    $attrs{'bold'} = 0;
	    $attrs{'reverse'} = 0;
	    $out .= $term->Tputs('me', 1);
	}
    }
}


# Clears the screen.
sub term_clear () {
    my $self = shift;
    $out .= $term->Tputs('cl', 1);
}


# Writes text using the current style at the current position.
sub term_addstr ($) {
    my $self = shift;
    $out .= $_[0];
}


# Repositions the cursor.
sub term_move ($$) {
    my $self = shift;
    my ($y,$x) = @_;
    $out .= $term->Tgoto('cm', $x, $y);
}


# Deletes all characters to the end of line.
sub term_delete_to_end () {
    my $self = shift;
    $out .= $term->Tputs('ce', 1);
}


# Inserts a new line at the current cursor position.
sub term_insert_line () {
    my $self = shift;
    $out .= $term->Tputs('al', 1);
}


# Deletes the line at the current cursor position.
sub term_delete_line () {
    my $self = shift;
    $out .= $term->Tputs('dl', 1);
}


# Inserts a character using the current style at the current cursor position.
sub term_insert_char () {
    my $self = shift;
    if (defined $term->Tputs('ic', 1)) {
	$out .= $term->Tputs('ic', 1);
    } else {
	$out .= $term->Tputs('im', 1) . ' ' . $term->Tputs('ei', 1) . "\b";
    }
}


# Deletes the character at the current cursor position.
sub term_delete_char () {
    my $self = shift;
    $out .= $term->Tputs('dc', 1);
}


# Rings the terminal bell
sub term_bell () {
    my $self = shift;
    $out .= $term->Tputs('bl', 1);
}

# Returns a character if one is waiting, or undef otherwise.
my $cbuf = '';
my $metaflag = 0;
my $ctrlflag = 0;
sub term_get_char () {
    my $self = shift;
    sysread(STDIN, $cbuf, 1024, length $cbuf);
    return undef unless (length $cbuf);
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

    if (($c eq "\n") || ($c eq "\r")) {
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
    my $self = shift;
    print $out;
    $out = '';
}


sub term_select ($$$$) {
    shift;
    my($rr, $wr, $er, $to) = @_;
 
    my $r = IO::Select->new(@$rr);
    my $w = IO::Select->new(@$wr);
    my $e = IO::Select->new(@$er);
    return IO::Select->select($r, $w, $e, $to);
}


1;
