# -*- Perl -*-
package LC::status_update;

# used for tie() with scalars.  From the programmer's standpoint, the resulting
# scalar will be perfectly normal except that it calls ui_status and stores
# the variable so it can be used on the status line.  Cool, eh?

# usage: tie $parse_state, 'LC::status_update', 'parse_state';


sub TIESCALAR {
    my($self,$varname)=@_;

    my %var;

    &main::log_debug("status_update: \"$varname\" init");

    $var{val}=undef;
    $var{varname}=$varname;

    return bless \%var,$self;    
}

sub FETCH {
    my($self)=@_;

#    &main::log_debug("$self->{varname} fetched ($self->{val})");
    return $self->{val};
}

sub STORE {
    my($self,$val)=@_;

    if ($val ne $self->{val}) {
	&main::log_debug("$self->{varname} changed to $val");
    }
    $self->{val}=$val;

    &main::set_status($self->{varname} => $self->{val});

    $self->{val}=$val;
}

1;



