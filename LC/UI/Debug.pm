# -*- Perl -*-

=head1 NAME

LC::UI:Debug - takes UI::Base and adds debugging output.

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

=cut

package LC::UI::Debug;
use LC::UI::Basic;

use vars qw(@ISA);
@ISA=("LC::UI::Basic");

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

sub ui_status {
    my $self=shift;

    print "ui_status @_\n" unless $self->{usable};
    return undef;
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

1;

