# -*- Perl -*-

=head1 NAME

LC::UI:Basic - tlily's dumbest user interface.

This is the simplest UI module possible.  

This module provides a simple text based UI functions, but you can't 
instantiate it directly.

=cut

package LC::UI::Basic;

sub ui_attr         { }
sub ui_filter       { }
sub ui_resetfilter  { }
sub ui_status       { }
sub ui_callback($$) { }
sub ui_remove_callback($$) { }
sub ui_password($)  { }

sub new {
    die "You can not use LC::UI::Basic as a UI.  Try LC::UI::Debug.\n";
}

sub ui_start {
    system("stty cbreak");
}

sub ui_end {
    system("stty sane");    
}

sub ui_prompt { 
    my $self=shift;
    print "\r@_";
}

sub ui_bell {
    my $self=shift;

    print STDOUT "";
    STDOUT->flush;
}

sub ui_output {
    my $self=shift;
    my %h=@_;

    my $text=strip_tags($h{Text});

    $self->{FileHandle} ||= "STDOUT";
    my $orig_selected=select ($self->{FileHandle});

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

    select($orig_selected);
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
       chomp($ret);
       return $ret;
    } else {
       return undef;
    }
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

