# -*- Perl -*-
# $Header: /data/cvs/tlily/extensions/program.pl,v 1.1 1998/10/21 04:42:49 mjr Exp $

use File::Copy 'cp';

$perms = undef;

sub verb_edit {
  if (scalar(@_) != 1) {
    ui_output("Usage: %verb edit (object):(verb)");
    return 0;
  }

  my $verb_spec = shift;

  # Do a minimal check of the verb spec here.
  unless ($verb_spec =~ /[^:]+:.+/) {
    ui_output("Usage: %verb edit (object):(verb)");
    return 0;
  }

  ui_output("(retrieving code for $verb_spec)");
  my @data = ();  # Will hold verb code
  $verbok = 1;    # Used in the following handler if the verb spec is no good

  cmd_process("\@list $verb_spec", sub {
      my($event) = @_;

      # If a previous call of this handler enountered an error, $verbok
      # will be false, and we should just return, and not do anything.
      return unless $verbok;

      if ($event->{Type} eq 'endcmd') {
        # We've retreived the full verb code, now to edit it.
        map { s/\\(.)/$1/g } @data;
        verb_set(VerbSpec=>$verb_spec,
                 Data=>\@data,
                 Edit=>1);
      } elsif ($event->{Type} eq 'unparsed') {
        if (($event->{Text} =~ /^That object does not define that verb\.$/) ||
            ($event->{Text} =~ /^Invalid object \'.*\'\.$/)) {
          # Encountered an error.
          $verbok = 0;
        } elsif ($event->{Text} =~/^That verb has not been programmed\.$/) {
          # Verb exists, but there's no code for it yet.
          # We'll provide a comment saying so as the verb code.
          $event->{ToUser} = 0;
          @data = ("/* This verb $verb_spec has not yet been written. */");
        } else {
          # Verb code line.
          $event->{ToUser} = 0;
          push @data, $event->{Text};
        }
      }
      return 0;
  });
}

sub verb_set(%) {
  my %args=@_;
  my $verb_spec=$args{VerbSpec};
  my $edit=$args{Edit};
  my @data=@{$args{Data}};

  my $tmpfile = "/tmp/tlily.$$";

  if ($edit) {

    local(*FH);
    my $mtime = 0;
  
    unlink($tmpfile);
    if (@data) {
      open(FH, ">$tmpfile") or die "$tmpfile: $!";
      foreach (@data) { chomp; print FH "$_\n"; }
      $mtime = (stat FH)[10];
      close FH;
    }
  
    ui_end();
    system("$config{editor} $tmpfile");
    ui_start();

    my $rc = open(FH, "<$tmpfile");
    unless ($rc) {
      ui_output("(verb buffer file not found)");
      return;
    }

    if ((stat FH)[10] == $mtime) {
      ui_output("(verb not changed)");
      close FH;
      unlink($tmpfile);
      return;
    }

    @data = <FH>;
    close FH;
  }

  # If the server detected an error, try to save the verb to a dead file.
  $id = register_eventhandler(Type => 'unparsed', Order => 'after',
          Call => sub {
              my($event,$handler) = @_;
              if ($event->{Raw} =~ /^Verb (not) programmed\./) {
                if ($1) {
                  ui_output("(Saved verb to dead.verb)");
                  unless (cp($tmpfile, "dead.verb")) {
                    ui_output("(Unable to save verb: $!)");
                  }
                }
                unlink($tmpfile);
                deregister_handler($handler->{Id});
              }
              return 0;
          }
        );
  server_send("\@program $verb_spec\n");
  foreach (@data) { chomp; server_send("$_\n") }
  server_send(".\n");
}

sub verb_list {
  if (scalar(@_) != 1) {
    ui_output("Usage: %verb list (object):(verb)");
    return 0;
  }

  my $verb_spec = shift;

  # Do a minimal check of the verb spec here.
  unless ($verb_spec =~ /[^:]+:.+/) {
    ui_output("Usage: %verb list (object):(verb)");
    return 0;
  }

  server_send("\@list $verb_spec\n");
}

sub verb_cmd {
  my ($cmd,@args) = split /\s+/, "@_";

  if ($cmd eq 'list') {
    verb_list(@args);
  } elsif ($cmd eq 'edit') {
    verb_edit(@args);
  } elsif ($cmd eq 'set') {
    unless (scalar(@args) == 2) {
      ui_output("Usage: %verb set (verb_spec) file");
      return 0;
    }
    verb_set(VerbSpec=>$verb_spec,
             Data=>\@data,
             Edit=>0);
  } else {
    ui_output("(perms = $perms)");
    ui_output("(unknown %verb command)");
  }
}

# This is a bit nasty.
# We want to figure out whether the user loading this module has
# programmer privs on the server.
# We will be sending an oob command "#$# options +usertype" to get
# the server to tell us what permissions we have.  Unfortunately,
# if you have no special permissions, the server doesn't give you
# an explicit NACK.  Fortunately, it _does_ send an %options line
# immediately afterwards, so also register a handler to look for
# that, and if we encounter that without encountering the %user_type
# line, we know we don't have any privs, and we unload the extension.


$id = register_eventhandler(Type => 'servercmd', Order => 'before',
                      Call => sub {
                         my($event,$handler) = @_;
                         if ($event->{Raw} =~ /%user_type ([pah]+)/) {
                            $event->{ToUser} = 0;
                           $perms = $1;
                           deregister_handler($handler->{Id});
                         }
                         return 0;
                       }
      );

register_eventhandler(Type => 'options',
          Call => sub {
            my($event,$handler) = @_;
            if ($event->{Raw} =~ /usertype/) {
              deregister_handler($handler->{Id});
              deregister_handler($id);
              if (!defined($perms) || $perms !~ /p/) {
                ui_output("You do not have programmer permissions on this server.");
                extension_unload("program");
              }
            }
            return 0;
          }
      );

server_send("\#\$\# options +usertype\n");

register_user_command_handler('verb', \&verb_cmd);

register_help_short("verb", "MOO verb manipulation functions");
register_help_long("verb", "
%verb list <verb_spec>    - Lists a verb.

%verb edit <verb_spec> - Edit a verb.

");


1;
