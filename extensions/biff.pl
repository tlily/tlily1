# $Header: /data/cvs/tlily/extensions/biff.pl,v 1.4 1998/06/23 02:02:45 mjr Exp $
#
# A Biff module
#
# TODO:
#  - Add support for regular POP
#  - Independant check intervals for each drop
#
use IO::Socket;
use IO::Select;

# Set the check interval (in seconds);
my $check_interval = $config{biff_interval} || 60;
my $check_eventid;        # id of the timed event handler for check_drops()
my $biff = '';            # Statusline variable
my $active;               # Is mail notification on?

# List of maildrops to check.  Each element is a hash, which contains access
# and state information for drop.  Listed below are the hash elements used
# for each type of maildrop.  Elements preceded by a '*' are internal, and
# transitory.  All other elements can be set from the config variable.
# (all)
#   type => contains one of the types defined below.
#  *status => The status of the drop.  Should be set either by the
#             check_<type> function, or an iohandler.  Is read by update_biff
#             which ors together the status of all drops, and uses that to
#             set the statusline and/or beep.  One of the following:
#               0 => No unread mail in drop
#               1 => Unread mail in drop
#               3 => New mail has just arrived in drop
# mbox - Standard  Unix mailbox.
#   path => Absolute pathname of the mbox
#  *mtime => mtime of mbox when last checked, as returned by -M
# maildir - Unix maildir.
#   path => Absolute pathname of the maildir
#  *mtime => mtime of most recent new message when last checked, as returned
#            by -M
# rpimchk - RPI lightweight POP check protocol
#   host => POP host
#   port => Port of mailcheck daemon
#   user => username to check
#  *sock => Handle of socket connection to server
#  *request => preconstructed request packet
#  *bytes => Number of bytes waiting for user
@drops;

# Check functions.  Each function is named check_<type>, and is passed a
# hashRef of the drop.

sub check_mbox(\%) {
  my $mboxRef = shift;
  my $mtime = -M $mboxRef->{path};
  my $atime = -A _;
  my $size = -s _;

  $mboxRef->{status} = 0;  # Default is no unread mail.
  if (-f _ && -s _ && ($mtime < -A _) ) {
    if (($mboxRef->{mtime} == 0) || ($mtime < $mboxRef->{mtime})) {
      $mboxRef->{mtime} = $mtime;  # Update mtime
      $mboxRef->{status} = 3;      # Ring bell
    } else {
      $mboxRef->{status} = 1;      # Unread mail
    }
  }
}

sub check_maildir(\%) {
  my $mdirRef = shift;
  my $mtime = undef;
  opendir(DH, "$mdirRef->{path}/new/");
  foreach (readdir(DH)) {
    next if /^\./;
    $mtime = ($mtime < -M "$mdirRef->{path}/new/$_")?$mtime:-M _;
  }
  closedir(DH);
  $mdirRef->{status} = 0;  # Default is no unread mail.
  if (defined($mtime)) {
    if ($mdirRef->{mtime} == 0 || $mtime < $mdirRef->{mtime}) {
      $mdirRef->{mtime} = $mtime;  # Update mtime
      $mdirRef->{status} = 3;      # Ring bell
    } else {
      $mdirRef->{status} = 1;      # Unread mail
    }
  }
}

sub check_rpimchk(\%) {
  my $mchkRef = shift;

  # Send a check request to the server.
  $mchkRef->{sock}->send($mchkRef->{request});
}

sub handle_rpimchk {
  my $evt = shift;

  foreach $drop (@drops) {
    if (($drop->{type} eq 'rpimchk') && ($drop->{sock} == $evt->{Handle})) {
      my $reply;
      $evt->{Handle}->recv($reply, 256);
      last if (length($reply) != 6);
      ($h1,$h2,$bytes)=unpack("CCN",$reply);
      last if ($h1 != 0x1 || $h2 != 0x2);
      if ($bytes == 0) {
        $drop->{status} = 0;
      } elsif ($bytes == $drop->{bytes}) {
        $drop->{status} = 1;
      } else {
        $drop->{status} = 3;
      }
      $drop->{bytes} = $bytes;
      last;
    }
  }
  # Since this happens after check_drops finishes, we have to update the
  # biff outselves.
  update_biff();
  return 0;
}

# Passed a hashref, outputs info about a drop to the UI.
sub print_drop($) {
  my %drop = %{shift()};

  if ($drop{type} eq 'mbox' || $drop{type} eq 'maildir') {
    ui_output("($drop{type} $drop{path})");
  } elsif ($drop{type} eq 'rpimchk') {
    ui_output("($drop{type} $drop{user}\@$drop{host}:$drop{port})");
  } else {
    ui_output("(Unknown maildrop type $drop{type})");
  }
}

# Goes through the list of drops, checking each one.
sub check_drops {
  my $status = 0;
  my $drop;
  foreach $drop (@drops) {
    &{"check_$drop->{type}"}($drop);
  }
  update_biff();
}

sub update_biff {
  my $status = 0;

  foreach $drop (@drops) {
    $status |= $drop->{status};
    $drop->{status} &= 1;  # Unset the bell bit.
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
    if ($active) {
      deregister_handler($check_eventid) if ($check_eventid);
      undef $check_eventid;
      foreach $drop (@drops) {
        if ($drop->{type} eq 'rpimchk') {
          $drop->{sock}->close();
          deregister_handler($drop->{r_eventid});
        }
      }
      $biff = '';
      redraw_statusline();
    }
    $active = 0;
    ui_output("(Mail notification off)");
    return 0;
  }

  if ($args eq 'on') {
    if ($active) {
      ui_output("(Mail notification already on)");
    } else {
      $check_eventid = register_timedhandler(Interval => $check_interval,
                                             Repeat => 1,
                                             Call => \&check_drops);

      foreach $drop (@drops) {
        $drop->{status} = 0;
        if ($drop->{type} eq 'rpimchk') {
          $drop->{port} = $drop->{port} || 1110;
          $drop->{sock} = new IO::Socket::INET(PeerAddr => "$drop->{host}",
                            PeerPort => "mailchk($drop->{port})",
                            Proto => "udp");
          $drop->{request} = pack("CCCa*",0x1,0x1,0x1,$drop->{user});
          $drop->{bytes} = 0;
          $drop->{r_eventid} = register_iohandler(Handle => $drop->{sock},
                                              Mode => 'r',
                                              Name => "mchk-$drop->{user}",
                                              Call => \&handle_rpimchk);
        }
      }
      $active = 1;
    }
    ui_output("(Mail notification on)");
    check_drops();
    return 0;
  }

  if ($args eq 'list') {
    if (@drops == undef) {
      ui_output("(No maildrops are being monitored)");
    } else {
      ui_output("(The following maildrops are monitored:)");
      map(print_drop($_),@drops);
    }
    if ($active) {
      ui_output("(Mail notification is on)");
    } else {
      ui_output("(Mail notification is off)");
    }
    return 0;
  }

  if ($args eq '') {
    map(print_drop($_), grep($_->{status} > 0, @drops)) ||
      ui_output("(No unread mail)");
    return 0;
  }

  ui_output("Usage: %biff [on|off|list]");
  return 0;
}

# Called when extension is unloaded.  Explicitly deregisters the timed
# handler, due to a bug that prevents it from happening automatically.
sub unload() {
  biff_cmd('off');
}


# Initialization

# Biff not yet active
$active = 0;

# Get maildrop list
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
Usage: %biff [on|off|list]

Monitors mailspool(s), and displays an indicator on the status line when
new mail arrives.  Will automatically look for MAILDIR, then MAIL
environment variables to determine a single default mail drop, if
none are set in the config variable.  The 'on' and 'off' arguments
turn notification on and off, the 'list' argument lists the maildrops
currently being monitored, and if no argument is given, %biff will list
those maildrops with unread mail.

Mail drops can be set via the %config{biff_drops} variable, by assigning
an arrayref of hashrefs to it, such as:
$config{biff_drops} = [{type => 'mbox', path => '/home/mjr/Mailbox'}];

Valid types and their requiremed elements are:
mbox - Standard Unix mbox file
  path => Absolute path to file
maildir - Maildir (as used in Qmail)
  path => Absolute path to directory
rpimchk - RPI lightweight POP mail check protocol
  host => mailcheck host
  port => mailcheck port (usually 1110)
  user => account username

The $config{biff_interval} can be set to the interval between maildrop polls,
in seconds.  If one of your maildrops is not an mbox or maildir, please
be considerate, and keep the interval above 5 minutes.  (That's 300 seconds
for those non-math types.)
END
);

# Start biff by default when loaded.
biff_cmd("on");
# Make sure the statusline gets updated.
redraw_statusline(1);
