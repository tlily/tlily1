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

use LC::Config;
use vars qw(@ISA);
@ISA=("LC::UI::Basic");

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

sub ui_output {
    my $self=shift;

    my %h;
    if (@_ == 1) {
	%h = (Text => $_[0]);
    } else {
	%h = @_;
    }

    my $text=strip_tags($h{Text});

    # NOTE:  This code DISABLES ssfe's word wrapping, because it indents really
    #        strangely when it does it.  Someone could write some word 
    #        wrapping code to drop in here, but.. 
    my ($char,$line);
    foreach $char (split //,$text) {
	$line .= $char;
	if (length($line) > $self->{ui_cols}) {
	    $line=~s/^$h{WrapChar}$h{WrapChar}/$h{WrapChar}/;
	    print "$line\n";
	    $line=$h{WrapChar};
	} elsif ($char =~ /[\r\n]/) {
	    $line=~s/^$h{WrapChar}$h{WrapChar}/$h{WrapChar}/;
	    print "$line";
	    $line=$h{WrapChar};
	}		
    }
    if ($line) {
	$line=~s/^$h{WrapChar}$h{WrapChar}/$h{WrapChar}/;	
	print "$line\n";
    }
}


sub ui_status {
    my ($self, $newstatus)=@_;

    my $newstatus=strip_tags($newstatus);

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

sub ui_select($$$$) {
    my($self, $rr, $wr, $er, $to) = @_;
 
    my $r = IO::Select->new(@$rr);
    my $w = IO::Select->new(@$wr);
    my $e = IO::Select->new(@$er);
    my @ret = IO::Select->select($r, $w, $e, $to);

    return @ret;
}

sub strip_tags {
    my ($text)=@_;
    $text =~ s/\\\\//g;
    $text =~ s/\\\<//g;
    $text =~ tr/</</;
    $text =~ s/\\(.)/$1/g;
    $text =~ tr//\\/;
    
    my $newtext;
    while (length $text) {
	if ($text =~ /^(([^\>]*)\>\>)/) {
	    # <<filter>>
	    $text = substr($text, length $1);
	} elsif ($text =~ /^(\/([^\>]*)\>)/) {
	    # </tag>
	    $text = substr($text, length $1);
	} elsif ($text =~ /^(([^\>]*)\>)/) {
	    # <tag>
	    $text = substr($text, length $1);
	} elsif ($text =~ /^(\r?\n)/) {
	    # newline
	    $text = substr($text, length $1);
	    $newtext .= "\n";
	} elsif ($text =~ /^([^\r\n]+)/) {
	    # text
	    $text = substr($text, length $1);
	    $newtext .= $1;
	}
    }                 
    return $newtext;
}

1;
