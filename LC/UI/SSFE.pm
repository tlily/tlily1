# -*- Perl -*-

=head1 NAME

LC::UI:SSFE - interface to the sirc "ssfe" program

Ssfe (split-screen front-end) is a small c program which provides a curses
interface to command-line programs.

Attributes, Color, Filters and callbacks are not supported by ssfe at this 
time.

You must have the "ssfe" program installed somewhere in your path.

It can be found at http://www.eleves.ens.fr:8080/home/espel/sirc/ssfe.c

=cut

package LC::UI::SSFE;

use LC::UI::Basic;
use LC::Config;
use vars qw(@ISA);
@ISA = ("LC::UI::Basic");

sub new {
    my ($class)=@_;
    
    my $self=bless {},$class;
    $self->{ui_cols} = 77;
    
    return $self;
}

sub ui_start {
    my ($self)=@_;

    push @::ORIGINAL_ARGV, "-ssfehack=1";

    my @SSFE=qw(ssfe -cooked -beep);

    if (! $config{"ssfehack"}) {
	exec @SSFE, $0, @::ORIGINAL_ARGV;
	exit(0);
    }
}

sub ui_end {
    my ($self)=@_;

}

sub ui_attr {
    my ($self)=shift;

}

sub ui_filter {
    my ($self)=shift;

}

sub ui_resetfilter {
    my $self=shift;

}

sub ui_status {
    my ($self, $newstatus)=@_;

    my $newstatus=LC::UI::Basic::strip_tags($newstatus);

    if ($self->{laststatus} ne $newstatus) {
	print "`#ssfe#s$newstatus\n";
	$self->{laststatus}=$newstatus;	
    }

    return undef;
}

sub ui_process {
    my $self=shift;

    # return a line of input, if available.
    my $buf;

    my $r = IO::Select->new(*STDIN);
    
    # i'm a little curious to know why this is being called when no input is
    # available...    
    return undef unless $r->can_read(0);

    # with ssfe, we always get a line of input.
    my $line=<STDIN>;

    if ($line eq "\n") { $line = " \n"; }

    return $line;
}

sub ui_callback($$) {
    my $self=shift;

}

sub ui_remove_callback($$) {
    my $self=shift;

}

sub ui_bell {
    my $self=shift;

    print "";
}

sub ui_password($) {
    my ($self,$pass)=@_;

    if ($pass) {
	print "`#ssfe#P\n";    
    }
}

sub ui_prompt {
    my ($self,$prompt)=@_;
    
    print "`#ssfe#p$prompt\n";
}

1;
