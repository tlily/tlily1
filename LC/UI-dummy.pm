# -*- Perl -*-

# This is a dummy UI module for the time being..

# How do you use this?  It's nice and kludgey.  Move the UI.pm file aside, 
# and ln -s UI-dummy.pm UI.pm.

# Also configure the $usable flag however you want it.

package LC::UI;

use Exporter;
use Carp qw(cluck);

@ISA = qw(Exporter);

@EXPORT = qw(&ui_start
	     &ui_end
	     &ui_attr
	     &ui_filter
	     &ui_resetfilter
	     &ui_clearattr
	     &ui_output
	     &ui_status
	     &ui_process
	     &ui_callback
	     &ui_remove_callback
	     &ui_bell
	     &ui_password
	     &ui_prompt
	     &ui_select
	     $ui_cols
	     &ui_escape
	    );
	    
$usable=1;	    

sub ui_start {
    print "ui_start\n";
    system("stty cbreak");
}

sub ui_end {
    print "ui_end\n";
    system("stty sane");    
}

sub ui_attr {
    print "ui_attr @_\n";
}

sub ui_filter {
    print "ui_filter @_\n";
}

sub ui_resetfilter {
    print "ui_resetfilter @_\n";
}

sub ui_output {
    my %h;
    if (@_ == 1) {
	%h = (Text => $_[0]);
    } else {
	%h = @_;
    }
    
    if ($usable) {
       # if I felt nice, i'd try to properly strip out the tags at this point,
       # but that's non-trivial, and for performance testing, I want to keep 
       # this as raw as I can.
       my $text=$h{Text};
       $text=~s/\<\/?sender\>//g;
       $text=~s/\<\/?dest\>//g;
       $text=~s/\<\/?emote\>//g;       
       $text=~s/\<\/?pubhdr\>//g;                     
       $text=~s/\<\/?pubmsg\>//g;              
       $text=~s/\<\/?privhdr\>//g;                            
       $text=~s/\<\/?privmsg\>//g;                     
       $text=~s/\<\/?pubmsg\>//g;              
       $text=~s/\<\/?usersend\>//g;
       $text=~s/\<\/?blurb\>//g;                            
       
       print "$text\n";
    } else {
       print "ui_output: $h{Text}\n";
    }       
}

sub ui_status {
    print "ui_status @_\n" unless $usable;
    return undef;
}

my $input;
sub ui_process {
    # return a line of input, if available.
    my $buf;

    my $r = IO::Select->new(*STDIN);
    
    # i'm a little curious to know why this is being called when no input is
    # available...    
    return undef unless $r->can_read(0);
    
    sysread(STDIN,$buf,1);
    if ($buf =~ /[]/) {
       $input=~s/.$//;
       print "\r$input";
       return undef;
    }
    $input .= $buf;
    
    if ($buf eq "\n") {
       my $ret=$input;
       $input="";
       return $ret;
    } else {
       return undef;
    }
}

sub ui_callback($$) {
    print "ui_callback @_\n";
}

sub ui_remove_callback($$) {
    print "ui_remove_callback @_\n";
}

sub ui_bell {
    print "ui_bell\n";
}

sub ui_password($) {
    print "ui_password\n";
}

sub ui_prompt {
    print "ui_prompt @_\n";
}

sub ui_escape {
    my ($line)=@_;
    $line =~ s/\</\\\</g; $line =~ s/\>/\\\>/g;
#    $line =~ s/\\\\([<>])/\\$1/g;  #what the heck!

    return $line;
}


sub ui_select($$$$) {
    my($rr, $wr, $er, $to) = @_;
 
    my $r = IO::Select->new(@$rr);
    my $w = IO::Select->new(@$wr);
    my $e = IO::Select->new(@$er);
    my @ret = IO::Select->select($r, $w, $e, $to);

    return @ret;
}

1;

