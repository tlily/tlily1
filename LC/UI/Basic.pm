# -*- Perl -*-

=head1 NAME

LC::UI:Basic - tlily's dumbest user interface.

This is the simplest UI module possible.  
It is not really designed to be used by end users, but should be very
useful for testing.  In addition, all UI modules should inherit from this 
one, and should overload ALL of these functions, and should provide the
$self->{ui_cols} variable (for the time being at least, I think that should
definitely be replaced with an accessor function or something more
intelligent..

Also configure the $usable flag however you want it.
  1 means to strip a lot of the tags and generally try to make the client
    somewhat usable in a pinch.  Good for testing.
  0 means to show everything, don't try to make it too pretty.  Good for other
    kinds of testing :)

Note that for whatever reason, you have to log in with your username
and password on the same line.

=cut

package LC::UI::Basic;

use vars qw(@ISA);


sub new {
    my ($class)=@_;
    
    my $self=bless {},$class;
    $self->{usable} = 1;
    $self->{ui_cols} = 80;
    
    return $self;
}

sub ui_start {
    my ($self)=@_;

    print "ui_start\n";
    system("stty cbreak");
}

sub ui_end {
    my ($self)=@_;

    print "ui_end\n";
    system("stty sane");    
}

sub ui_attr {
    my ($self)=shift;

    print "ui_attr @_\n";
}

sub ui_filter {
    my ($self)=shift;

    print "ui_filter @_\n";
}

sub ui_resetfilter {
    my $self=shift;

    print "ui_resetfilter @_\n";
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

    # NOTE:  This code does not do word wrapping.
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
    my $self=shift;

    print "ui_status @_\n" unless $self->{usable};
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
    
    sysread(STDIN,$buf,1);
    if ($buf =~ /[]/) {
       $self->{input}=~s/.$//;
       print "\r$self->{input}";
       return undef;
    }
    $self->{input} .= $buf;
    
    if ($buf eq "\n") {
       my $ret=$self->{input};
       $self->{input}="";
       return $ret;
    } else {
       return undef;
    }
}

sub ui_callback($$) {
    my $self=shift;

    print "ui_callback @_\n";
}

sub ui_remove_callback($$) {
    my $self=shift;

    print "ui_remove_callback @_\n";
}

sub ui_bell {
    my $self=shift;

    print "ui_bell\n";
}

sub ui_password($) {
    my $self=shift;

    print "ui_password\n";
}

sub ui_prompt {
    my $self=shift;

    print "ui_prompt @_\n";
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

