# -*- Perl -*-
# $Header: /data/cvs/tlily/LC/UI/OutputWindow.pm,v 1.1 1998/10/24 20:41:35 josh Exp $

=head1 NAME

LC::UI:OutputWindow - open an xterm and send text to it.

Currently Prompts, Status, Attributes, Color, Filters, Input, and Callbacks
are not supported.

=cut

package LC::UI::OutputWindow;

use LC::UI::Basic;
use IO::Pty;
use POSIX qw(:termios_h);
use vars qw($xterm_pid @ISA);
@ISA = ("LC::UI::Basic");

sub new {
    my ($class)=@_;
    
    my $self=bless {},$class;
    $self->{ui_cols} = 77;
    
    return $self;
}

sub ui_start {
    my ($self)=@_;

    # permit file descriptors to be passed on to the child process.
    my $fdmax=$^F;  $^F=255;
    my $pty = new IO::Pty;
    $^F=$fdmax;
    
    my $ptynum = substr($pty->ttyname,-2,2);
    my $fd = fileno($pty);
    my $slave=$pty->slave;
    my $slave_fd = fileno($slave);
    my $xterm = "xterm -S$ptynum$fd";

    # Turn of input echoing on the xterm.
    my $termios = new POSIX::Termios();
    $termios->getattr($slave_fd) || die "getattr: $!\n";
    my $lflag = $termios->getlflag;
    $lflag &= ~(POSIX::ICANON|POSIX::ECHO);
    $termios->setlflag($lflag);
    $termios->setattr($slave_fd,POSIX::TCSANOW) || die "setattr: $!\n";
    
    # fork it off.
    if (($self->{xterm_pid}=fork()) == 0) {
	setpgrp;
	exec ($xterm);
    }
    
    # wait for the xterm to start.
    sleep (3);

    $self->{pty}=$pty;
    $self->{FileHandle}=$slave;
}

sub ui_end {
    my ($self)=@_;

    kill 15, $self->{xterm_pid};
}

# return a line of input, if available.  Currently, input is not implemented
# for this module.
sub ui_process {
    my $self=shift;

    return undef;
}

1;




