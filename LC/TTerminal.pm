# -*- Perl -*-
# $Header: /data/cvs/tlily/LC/TTerminal.pm,v 2.1 1998/06/12 08:56:17 albert Exp $
package LC::TTerminal;

use IO::Select;
use Term::Cap;
eval "use Term::Size;";
my $termsize_installed;
if ("$@") { 
  warn("** WARNING: Unable to load Term::Size: **\n");
  $termsize_installed=0;
  sleep 2;
} else {
  $termsize_installed=1;
}
use POSIX;

my %attrs = ('bold' => 0,
             'reverse' => 0);

my $term_up = 0;
my $resize_cb;

my $term_resize_flag = 0;

my $term;
my $out = '';

my $save_c_lflag;
my $save_vmin;
my $save_vtime;


sub new {
    bless {};
}


sub term_lines () { $term_lines; }
sub term_cols () { $term_cols; }


# Initialize the terminal.
sub term_init ($) {
    my $self = shift;
    return if ($term_up);
    $resize_cb = $_[0];
    if ($termsize_installed) {
	($term_cols, $term_lines) = Term::Size::chars;
    } else {
	($term_cols, $term_lines) = (80,24);
    }

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

    eval '$term = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };';

    if ($@) {
	if ($ENV{TERM} eq "vt100") {
	    $ENV{TERMCAP}='vt100|vt100-am|vt100am|dec vt100:do=^J:co#80:li#24:cl=50\E[;H\E[2J:sf=5\ED:le=^H:bs:am:cm=5\E[%i%d;%dH:nd=2\E[C:up=2\E[A:ce=3\E[K:cd=50\E[J:so=2\E[7m:se=2\E[m:us=2\E[4m:ue=2\E[m:md=2\E[1m:mr=2\E[7m:mb=2\E[5m:me=2\E[m:is=\E[1;24r\E[24;1H:rf=/usr/share/lib/tabset/vt100:rs=\E>\E[?3l\E[?4l\E[?5l\E[?7h\E[?8h:ks=\E[?1h\E=:ke=\E[?1l\E>:ku=\EOA:kd=\EOB:kr=\EOC:kl=\EOD:kb=^H:ho=\E[H:k1=\EOP:k2=\EOQ:k3=\EOR:k4=\EOS:pt:sr=5\EM:vt#3:xn:sc=\E7:rc=\E8:cs=\E[%i%d;%dr:';
	} elsif ($ENV{TERM} =~ /xterm/) {
	    $ENV{TERM}="xterm";
	    $ENV{TERMCAP}='xterm|vs100|xterm terminal emulator (X Window System):AL=\E[%dL:DC=\E[%dP:DL=\E[%dM:DO=\E[%dB:IC=\E[%d@:UP=\E[%dA:al=\E[L:am:bs:cd=\E[J:ce=\E[K:cl=\E[H\E[2J:cm=\E[%i%d;%dH:co#80:cs=\E[%i%d;%dr:ct=\E[3k:dc=\E[P:dl=\E[M:im=\E[4h:ei=\E[4l:mi:ho=\E[H:is=\E[r\E[m\E[2J\E[H\E[?7h\E[?1;3;4;6l\E[4l:rs=\E[r\E[m\E[2J\E[H\E[?7h\E[?1;3;4;6l\E[4l\E<:k1=\EOP:k2=\EOQ:k3=\EOR:k4=\EOS:kb=^H:kd=\EOB:ke=\E[?1l\E>:kl=\EOD:km:kn#4:kr=\EOC:ks=\E[?1h\E=:ku=\EOA:li#65:md=\E[1m:me=\E[m:mr=\E[7m:ms:nd=\E[C:pt:sc=\E7:rc=\E8:sf=\n:so=\E[7m:se=\E[m:sr=\EM:te=\E[2J\E[?47l\E8:ti=\E7\E[?47h:up=\E[A:us=\E[4m:ue=\E[m:xn:';
	}  else {
	    die "$@\n(no fallback termcap for $ENV{TERM}, try xterm or vt100)\n";
	}
	$term = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
    }

    $term->Trequire(qw/cm/);

    my $term_flags = 0;
    fcntl(STDIN,F_GETFL,$term_flags) or die("fcntl: $!\n");
    $term_flags |= O_NONBLOCK;
    fcntl(STDIN,F_SETFL,$term_flags) or die("fcntl: $!\n");

    $| = 1;

    $main::config{mono} = 1;

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
    my @ret = IO::Select->select($r, $w, $e, $to);

    if ($term_resize_flag) {
	$term_resize_flag = 0;
	if ($termsize_installed) {
	    ($term_cols, $term_lines) = Term::Size::chars;
	} else {
	    ($term_cols, $term_lines) = (80,24);
	}
	&$resize_cb if (defined $resize_cb);
    }

    return @ret;
}


1;
