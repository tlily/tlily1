# -*- Perl -*-

=head1 NAME

LC::UI:SSFE - interface to the sirc "ssfe" program

Ssfe (split-screen front-end) is a small c program which provides a curses
interface to command-line programs.

Attributes, Color, Filters and callbacks are not supported by ssfe at this 
time.

You must have the "ssfe" program installed somewhere in your path.

It can be found at http://www.eleves.ens.fr:8080/home/espel/sirc/ssfe.c

Bugs:
I note that prompts do not seem to work after the first one.
This appears to be a bug in ssfe itself, but I am not sure.  I might be 
using the ssfe "p" command incorrectly or something.

=cut

package LC::UI::SSFE;

use LC::UI::Basic;
use LC::Config;
use vars qw(@ISA);
@ISA = ("LC::UI::Basic");

# count of how many LC::UI::Native's are running.
my $ssfe_ui_running = 0;

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

    if ($ssfe_ui_running) {
	die "Error:  Only one LC::UI::SSFE UI can be run at a time.\n";
    }

    $ssfe_ui_running++;
}

sub ui_end {
    my ($self)=@_;

    $ssfe_ui_running--;
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
    chomp($line);

    if ($line eq "") { $line = " "; }

    return $line;
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
