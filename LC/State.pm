# -*- Perl -*-
package LC::State;

use Exporter;
use LC::UI;
use LC::Command;
use LC::parse;
use LC::Event;
use LC::StatusLine;
use POSIX;

@ISA = qw(Exporter);

@EXPORT = qw(&expand_name
	     &set_user_state
	     &get_user_state
	     &rename_user
	     &destroy_user
	     &set_disc_state
	     &get_disc_state
	     &destroy_disc
	     &state_sync
	     &state_init
	     &user_name);


my %Users = ();
my %Discs = ();


# Map a user-entered name to a canonical lily name.
sub expand_name ($) {
    my($name) = @_;
    my $disc;

    $name = tolower($name);
    $name =~ tr/ /_/;
    $disc = 1 if ($name =~ s/^-//);

    # Check for an exact match.
    if (!$disc && $Users{$name}) {
	return $Users{$name}->{Name};
    }
    if ($Discs{$name}) {
	return '-' . $Discs{$name}->{Name};
    }
	
    @unames = keys %Users;
    @dnames = keys %Discs;
	
    # Check for a prefix match.
    unless ($disc) {
	@m = grep { index($_, $name) == 0 } @unames;
	return $Users{$m[0]}->{Name} if (@m == 1);
	return undef if (@m > 1);
    }
    @m = grep { index($_, $name) == 0 } @dnames;
    return '-' . $Discs{$m[0]}->{Name} if (@m == 1);
    return undef if (@m > 1);
	
    # Check for a substring match.
    unless ($disc) {
	@m = grep { index($_, $name) != -1 } @unames;
	return $Users{$m[0]}->{Name} if (@m == 1);
	return undef if (@m > 1);
    }
    @m = grep { index($_, $name) != -1 } @names;
    return '-' . $Discs{$m[0]}->{Name} if (@m == 1);
    return undef if (@m > 1);

    return undef;
}


##########################################################################
# Users


# Set state information for a user.  Takes a hash with a set
# of state parameters.  The key parameter 'Name' is required.
sub set_user_state (%) {
    my(%params) = @_;

    my $name = tolower($params{Name});
    $name =~ tr/ /_/;

    my $href = $Users{$name};
    unless ($href) {
	my %h = ();
	$href = \%h;
	$Users{$name} = \%h;
    }

    foreach (keys %params) {
	$$href{$_} = $params{$_};
    }
}


# Get state information for a user.  Takes a hash with the state variables
# to fetch as keys, and references to variables as values.  The key 'Name'
# is required, and indicates what to return information on.
sub get_user_state (%) {
    my(%params) = @_;

    my $name = tolower($params{Name});
    $name =~ tr/ /_/;
    delete $params{Name};

    my $href = $Users{$name};
    return 0 unless ($href);

    foreach (keys %params) {
	my $vref = $params{$_};
	$$vref = $$href{$_};
    }

    return 1;
}


# Moves state information for a user to the user's new pseudo.
sub rename_user ($$) {
    my($old,$new) = @_;

    $old = tolower($old);
    $old =~ tr/ /_/;

    $new = tolower($old);
    $new =~ tr/ /_/;

    $Users{$new} = $Users{$old};
    delete $Users{$old};
}


# Destroys state information for a user.
sub destroy_user ($) {
    my($user) = @_;

    $user = tolower($user);
    $user =~ tr/ /_/;
    delete $Users{$user};
}


# Returns the pseudo being used by the user.
sub user_name () {
    return $Me;
}



##########################################################################
# Discussions


# Set state information for a discussion.  Takes a hash with a set
# of state parameters.  The key parameter 'Name' is required.
sub set_disc_state (%) {
    my(%params) = @_;

    my $name = tolower($params{Name});
    $name =~ tr/ /_/;
    $name =~ s/^-//;

    my $href = $Discs{$name};
    unless ($href) {
	my %h = ();
	$href = \%h;
	$Discs{$name} = \%h;
    }

    foreach (keys %params) {
	$$href{$_} = $params{$_};
    }
}


# Get state information for a discussion.  Takes a hash with the state
# variables to fetch as keys, and references to variables as values.  The
# key 'Name' is required, and indicates what to return information on.
sub get_disc_state (%) {
    my(%params) = @_;

    my $name = tolower($params{Name});
    $name =~ tr/ /_/;
    $name =~ s/^-//;
    delete $params{Name};

    my $href = $Discs{$name};
    return 0 unless ($href);

    foreach (keys %params) {
	my $vref = $params{$_};
	$$vref = $$href{$_};
    }

    return 1;
}


# Destroys state information for a discussion.
sub destroy_disc ($) {
    my($disc) = @_;

    $disc = tolower($disc);
    $disc =~ tr/ /_/;
    $name =~ s/^-//;
    delete $Discs{$disc};
}


# Pulls all state information back into sync.
sub state_sync () {
    %Users = ();
    %Discs = ();

    cmd_process('/who me', sub {
	my($event) = @_;
	$event->{ToUser} = 0;
	if ($event->{Type} eq 'who') {
	    $Me = $event->{User};
	    $event->{IsUser} = 1;
	}
	return 0;
    });

    cmd_process('/who everyone', sub {
	my($event) = @_;
	$event->{ToUser} = 0;
	return 0;
    });

    cmd_process('/what all', sub {
	my($event) = @_;
	$event->{ToUser} = 0;
	return 0;
    });
}


# Registers the handlers required to maintain lily state information.
sub state_init () {
    register_eventhandler(Type => 'rename',
			  Order => 'before',
			  Call => sub {
	my($event,$handler) = @_;
	$event->{From} = $Me unless $event->{From};
	if ($event->{From} eq $Me) {
	    $event->{IsUser} = 1;
	    $Me = $event->{To};
	}
	rename_user($event->{From}, $event->{To});
	return 0;
    });

    register_eventhandler(Type => 'disccreate',
			  Order => 'before',
			  Call => sub {
	my($event,$handler) = @_;
	set_disc_state(Name => $event->{Name});
	return 0;
    });

    register_eventhandler(Type => 'discdestroy',
			  Order => 'before',
			  Call => sub {
	my($event,$handler) = @_;
	destroy_disc($event->{Name});
	return 0;
    });

    register_eventhandler(Type => 'who',
			  Order => 'before',
			  Call => sub {
	my($event,$handler) = @_;
	set_user_state(Name => $event->{User});
	return 0;
    });

    register_eventhandler(Type => 'what',
			  Order => 'before',
			  Call => sub {
	my($event,$handler) = @_;
	set_disc_state(Name => $event->{Disc});
	return 0;
    });

    register_eventhandler(Type => 'userstate',
			  Order => 'before',
			  Call => sub {
	my($event,$handler) = @_;
	$event->{User} = $Me unless ($event->{User});
	$event->{IsUser} = 1 if ($event->{User} eq $Me);
	if ($event->{To} eq 'gone') {
	    destroy_user($event->{User});
	} elsif ($event->{From} eq 'gone') {
	    set_user_state(Name => $event->{User});
	}
	return 0;
    });

    register_eventhandler(Type => 'blurb',
			  Order => 'before',
			  Call => sub {
	my($event,$handler) = @_;
	$event->{User} = $Me unless ($event->{User});
	$event->{IsUser} = 1 if ($event->{User} eq $Me);
	return 0;
    });
}


1;
