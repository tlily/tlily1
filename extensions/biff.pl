# $Header: /data/cvs/tlily/extensions/biff.pl,v 1.2 1998/06/13 21:57:28 mjr Exp $
#
# A Biff module
#

my $interval = 10;  # Check drops every x seconds.
my $event_id;      # id of the timed event handler (check_drops())
my $biff = '';     # Statusline variable

# List of maildrops to check.  Each element is a hash, which contains access
# and state information for drop.  One element of the has is 'Type', which
# contains the type of the drop.  The current types supported are:
#  mbox - Standard  Unix mailbox.
#   path => Absolute pathname of the mbox
#   mtime => mtime of mbox when last checked, as returned by -M
#  maildir - Unix maildir.
#   path => Absolute pathname of the maildir
#   mtime => mtime of most recent new message when last checked, as returned
#            by -M
my @drops;

# Check functions.  Each function is named check_<type>, and is passed a
# hashRef, and must return one of:
#  0  - No unread new mail in drop.
#  1  - Unread new mail in drop
#  3  - Mail has just arrived - causes a bell

sub check_mbox($) {
  my $mboxRef = shift;
  my $retval = 0;  # Default return value is no unread mail
  my $mtime = -M $mboxRef->{path};
  if (-f _ && -s _ && ($mtime < -A _) ) {
    if (($mboxRef->{mtime} == 0) || ($mtime < $mboxRef->{mtime})) {
      $mboxRef->{mtime} = $mtime;
      $retval = 3;  # Ring bell
    } else {
      $retval = 1;  # Unread mail
    }
  }
  return $retval;
}

sub check_maildir($) {
  my $mdirRef = shift;
  my $retval = 0;
  my $mtime = undef;
  opendir(DH, "$mdirRef->{path}/new/");
  foreach (readdir(DH)) {
    next if /^\./;
    $mtime = ($mtime < -M "$mdirRef->{path}/new/$_")?$mtime:-M _;
  }
  closedir(DH);
  if (defined($mtime)) {
    if ($mdirRef->{mtime} == 0 || $mtime < $mdirRef->{mtime}) {
      $mdirRef->{mtime} = $mtime;
      $retval = 3;  # Ring bell
    } else {
      $retval = 1;  # Unread mail
    }
  }
}

# Passed a hashref, outputs info about a drop to the UI.
sub print_drop($) {
  my %drop = %{shift()};

  if ($drop{type} == 'mbox' || $drop{type} == 'maildir') {
    ui_output("($drop{type} $drop{path})");
  } else {
    ui_output("(Unknown maildrop type $drop{type})");
  }
}

# Goes through the list of drops, checking each one.
sub check_drops {
  my $status = 0;
  my $drop;
  foreach $drop (@drops) {
    $status |= &{"check_$drop->{type}"}($drop);
  }
  if ($status) {
    $biff = "Mail";
    ui_bell() if ($status == 3);
  } else {
    $biff = '';
  }
  redraw_statusline();
}

sub biff_cmd($) {
  my($args) = @_;

  if ($args eq 'off') {
    deregister_handler($event_id) if ($event_id);
    undef $event_id;
    $biff = '';
    redraw_statusline();
    ui_output("(Mail notification off)");
    return 0;
  }

  if ($args eq 'on') {
    $event_id = register_timedhandler(Interval => $interval,
                                      Repeat => 1,
                                      Call => \&check_drops);

    ui_output("(Mail notification on)");
    check_drops();
    return 0;
  }

  if ($args == undef) {
    if (@drops == undef) {
      ui_output("(No maildrops are being monitored)");
    } else {
      ui_output("(The following maildrops are monitored:)");
      map(print_drop($_),@drops);
    }
    if ($event_id == undef) {
      ui_output("(Mail notification is off)");
    } else {
      ui_output("(Mail notification is on)");
    }
    return 0;
  }

  ui_output("Usage: %biff [on|off]");
  return 0;
}

# Called when extension is unloaded.  Explicitly deregisters the timed
# handler, due to a bug that prevents it from happening automatically.
sub unload() {
  deregister_handler($event_id);
}


# Initialization
if ($config{biff_drops}) {
  ui_output("(Setting maildrop list from config file)");
  @drops = @{$config{biff_drops}};
} else {
  if ($ENV{MAILDIR}) {
    ui_output("(Setting maildrop to MAILDIR environ)");
    push @drops, {'type' => 'maildir', 'path' => $ENV{MAILDIR}};
  } elsif ($ENV{MAIL}) {
    ui_output("(Setting maildrop to MAIL environ)");
    push @drops, {'type' => 'mbox', 'path' => $ENV{MAIL}};
  } else {
    ui_output("(Can not find a maildrop!)");
    return 0;
  }
}

register_statusline(Var => \$biff, Position => "PACKRIGHT");
register_user_command_handler('biff', \&biff_cmd);
register_help_short('biff', 'Monitor mail spool for new mail');
register_help_long('biff', <<END
Usage: %biff [on|off]

Monitors mailspool(s), and displays an indicator on the status line when
new mail arrives.
END
);

biff_cmd("on");
