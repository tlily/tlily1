# -*- Perl -*-
package LC::State;

=head1 NAME

LC::State - user/discussion state maintenance.

=head1 DESCRIPTION

The State module maintains a list of users and discussions (as well as some
information on them), and the pseudo used by the current user.  It performs
some editing on events to fill out information the Parse module is unable
to determine.  It also keeps a list of groups.

=head2 Canonical names

Lily permits the use of abbreviations to refer to users and discussions.
Every user and discussion, however, has a 'canonical' name -- the name
lily uses to refer to that entity.  (In the case of a user, this name is
the user\'s pseudo, which may change with time.)

=head2 User state information

An unlimited number of state properties may be stored for each user; at
this time, however, the only one in use is the 'Name' property, which
contains the canonical lily name of the user.

=head2 Discussion state information

An unlimited number of state properties may be stored for each discussion; at
this time, however, the only one in use is the 'Name' property, which
contains the canonical lily name of the discussion.

=head2 Functions

=over 10

=item expand_name()

Translates a name into a full lily name.  For example, 'cougar' might become
'Spineless Cougar', and 'comp' could become '-computer'.  The name returned
will be identical to canonical one used by lily for that abberviation,
with the exception that discussions are returned with a preceding '-'.
If the name is an exact match (modulo case) for a group, the group name
is returned.  Substrings of groups are not, however, expanded.  This is
in line with current lily behavior.

If $config{expand_group} is set, groups will be expanded into a
comma-separated list of their members.

    expand_name('comp');

=item get_user_state()

Retrieves state parameters for a user.  This function takes a hash as a
paramters, with parameter names as the keys, and variable references as the
values.  The 'Name' parameter is required, and should specify the name
of the user to retrieve information for.

    get_user_state(Name => 'damien',
		   Parameter => \$parameter);

=item get_disc_state()

Retrieves state parameters for a discussion.  This function takes a hash as a
paramters, with parameter names as the keys, and variable references as the
values.  The 'Name' parameter is required, and should specify the name
of the discussion to retrieve information for.

    get_user_state(Name => 'computer',
		   Parameter => \$parameter);

=item state_sync()

Forces a full synchronization of the state database.  Example:

    state_sync();

=item user_name

The pseudo used by the current user.  Example:

    $Me = user_name;

=back

=head1 EVENTS

=over 10

=item rename, userstate, blurb

The 'Name' field is set to the pseudo of the current user if it is undefined.
The 'IsUser' field is set to 1 if the event pertains to the current user.
See Parse.pm for a complete description of these events.

=item who

The 'IsUser' field is set to 1 if the event pertains to the current user.
See Parse.pm for a complete description of this event.

=item disccreate, discdestroy, what

See Parse.pm for a complete description of these events.

=back

=head1 COMMANDS

=over 10

=item %sync

Resynchronizes the user and discussion databases with the server.

=back

=cut


use Exporter;
use LC::UI;
use LC::Command;
use LC::parse;
use LC::Event;
use LC::StatusLine;
use LC::User;
use LC::Config;

@ISA = qw(Exporter);

@EXPORT = qw(&expand_name
	     &get_user_state
	     &get_disc_state
	     &state_sync
	     &user_name);


# Do not my these, as they can be useful for debugging.
%Users = ();
%Discs = ();
%Groups = ();

my $state_sync_count = 0;


# Map a user-entered name to a canonical lily name.
sub expand_name ($) {
    my($name) = @_;
    my $disc;

    $name = lc($name);
    $name =~ tr/ /_/;
    $disc = 1 if ($name =~ s/^-//);

    # Check for an exact match.
    if ($Groups{$name}) {
	if ($config{expand_group}) {
	    return join(',', @{$Groups{$name}->{Members}});
	} else {
	    return $Groups{$name}->{Name};
	}
    }
    if (!$disc && $Users{$name}) {
	return $Users{$name}->{Name};
    }
    if ($Discs{$name}) {
	return '-' . $Discs{$name}->{Name};
    }
	
    @unames = keys %Users;
    @dnames = keys %Discs;

    # Check the "preferred match" list.
    if (ref($config{prefer}) eq "ARRAY") {
	my $m;
	foreach $m (@{$config{prefer}}) {
	    $m = lc($m);
	    return $m if (index($m, $name) == 0);
	    return $m if ($m =~ /^-/ && index($m, $name) == 1);
	}
    }
	
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

    my $name = lc($params{Name});
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

    my $name = lc($params{Name});
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

    $old = lc($old);
    $old =~ tr/ /_/;

    my $newt = lc($new);
    $newt =~ tr/ /_/;

    $Users{$newt} = $Users{$old};
    $Users{$newt}->{Name} = $new;
    delete $Users{$old};
}


# Destroys state information for a user.
sub destroy_user ($) {
    my($user) = @_;

    $user = lc($user);
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

    my $name = lc($params{Name});
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

    my $name = lc($params{Name});
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

    $disc = lc($disc);
    $disc =~ tr/ /_/;
    $name =~ s/^-//;
    delete $Discs{$disc};
}


# Event handler for group updates.
sub group_handler ($$) {
    my($event,$handler) = @_;
    my $group = lc($event->{Group});
    if (!defined $Groups{$group}) {
	@cand = grep { index($_, $group) == 0 } (keys %Groups);
	if (scalar(@cand) == 1) {
	    $group = $cand[0];
	    $event->{Group} = $Groups{$group}->{Name};
	} else {
	    $Groups{$group}->{Name} = $event->{Group};
	}
    }
    if ($event->{Members}) {
	$Groups{$group}->{Members} = $event->{Members};
    } else {
	delete $Groups{$group};
    }
    return 0;
}


# Pulls all state information back into sync.
sub state_sync () {
    %Users = ();
    %Discs = ();
    %Groups = ();

    my $decr_sync = sub {
	$state_sync_count--;
	if ($state_sync_count == 0) {
	    $status_SyncState = '';
	    redraw_statusline();
	}
    };

    if ($state_sync_count > 0) {
	ui_output("(sync already in progress)");
	return;
    }

    if ($state_sync_count == 0) {
	$status_SyncState = 'sync';
	redraw_statusline();
    }
    $state_sync_count = 4;

    cmd_process('/who me', sub {
	my($event) = @_;
	&$decr_sync if ($event->{Type} eq 'endcmd');
	$event->{ToUser} = 0;
	if ($event->{Type} eq 'who') {
	    $Me = $event->{User};
	    $event->{IsUser} = 1;
	}
	return 0;
    });

    cmd_process('/who everyone', sub {
	my($event) = @_;
	&$decr_sync if ($event->{Type} eq 'endcmd');
	$event->{ToUser} = 0;
	return 0;
    });

    cmd_process('/what all', sub {
	my($event) = @_;
	&$decr_sync if ($event->{Type} eq 'endcmd');
	$event->{ToUser} = 0;
	return 0;
    });

    cmd_process('/group', sub {
	my($event) = @_;
	&$decr_sync if ($event->{Type} eq 'endcmd');
	$event->{ToUser} = 0;
	return 0 unless ($event->{Type} eq 'unparsed');
	return 0 if ($event->{Text} =~ /^Group      Members/);
	return 0 if ($event->{Text} =~ /^-----/);
	my $group = substr($event->{Text}, 0, 11);
	$group =~ s/\s*$//;
	my @members = split /, /, substr($event->{Text}, 11);
	$Groups{lc($group)}->{Name} = $group;
	$Groups{lc($group)}->{Members} = \@members;
	return 0;
    });
}


# Registers the handlers required to maintain lily state information.
sub state_init () {
    register_eventhandler(Type => 'connected',
			  Call => sub {
        my($event,$handler) = @_;
	state_sync();
	deregister_handler($handler->{Id});
	return 0;
			  });

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
	$event->{IsUser} = 1 if ($event->{User} eq $Me);
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

    register_eventhandler(Type => 'group',
			  Order => 'before',
			  Call => \&group_handler);

    register_user_command_handler('group', sub {
	my $group;
	ui_output("Group      Members");
	ui_output("-----      -------");
	foreach $group (sort keys %Groups) {
	    ui_output(sprintf("%-11s%s",
			      $Groups{$group}->{Name},
			      "@{$Groups{$group}->{Members}}"));
	}
    });

    register_user_command_handler('sync', sub {
	my($args) = @_;
	if ($args eq '-f') {
	    $state_sync_count = 0;
	} elsif ($args) {
	    ui_output('(Usage: %sync [-f])');
	    return 0;
	}
	ui_output('(Synchronizing state with the server)');
	state_sync();
	return 0;
    });

    register_help_short('sync', 'synchronize state with server');
    register_help_long('sync', <<END
Usage: %sync [-f]

The %sync command synchronizes the internal user and discussion databases with the server.  The -f option forces a sync to begin even if a sync is already in progress.  This is useful if tlily freezes in the sync state (which is caused by a network buffer overflow on the server at an unfortunate time).
END
		      );
}

state_init();

1;
