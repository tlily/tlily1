package LC::time_stamp;

# usage: tie $timestamp, 'LC::time_stamp';


sub TIESCALAR {
    my($self)=@_;
    my $var;

    return bless \$var,$self;    
}

sub FETCH {
    ($sec,$min,$hour) = localtime(time);
    return sprintf ("%2.2d:%2.2d:%2.2d",$hour,$min,$sec);
}

1;



