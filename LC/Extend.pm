# -*- Perl -*-
# $Header: /data/cvs/tlily/LC/Extend.pm,v 2.5 1998/10/25 18:50:32 mjr Exp $
package LC::Extend;

use Exporter;
use LC::ExoSafe;
use File::Basename;
use LC::Server;
use LC::Command;
use LC::Config;
use LC::Event;

BEGIN {
    if ($main::load_ui) {
	require LC::User;      LC::User->import();
	require LC::State;     LC::State->import();
	require LC::SubClient; LC::SubClient->import();
	require LC::UI;        LC::UI->import();
    } else {
	sub ui_output { print "@_\n"; } 
    }
}


#require "dumpvar.pl";

@ISA = qw(Exporter);

@EXPORT = qw(&extension
	     &extension_unload
	     &load_extensions);

# initial version, 10/24/97, Josh Wilmes

# Provide a secure environment for user extensions to TigerLily.  We use
# an ExoSafe to provide strict control over what the extensions have access to.


my %Extensions = ();
my @loading_exts = ();


sub extension($;$) {
    my ($name,$verbose)=@_;
    my $filename;
    my @share=();

    if (-f $name) {
	$filename = $name;
	$name = basename($name, ".pl", ".PL");
    }

    if (defined $Extensions{$name}) {
	ui_output("(extension \"$name\" already loaded)");
	return ;
    }

    if (!defined $filename) {
	my @ext_dirs = ("$ENV{HOME}/.lily/tlily/extensions", $main::TL_EXTDIR);
	my $dir;
	foreach $dir (@ext_dirs) {
	    if (-f "${dir}/${name}.pl") {
		$filename = "${dir}/${name}.pl";
		last;
	    }
	}
    }

    if (!defined $filename) {
	ui_output("(cannot locate extension \"$name\")");
	return;
    }
    
    ui_output("(loading \"$name\" from \"$filename\")") if ($verbose);

    my $safe=new ExoSafe;

    push @share,@LC::UI::EXPORT;
    push @share,@LC::Server::EXPORT;
    push @share,@LC::parse::EXPORT;
    push @share,@LC::User::EXPORT; 
    push @share,@LC::Command::EXPORT;
    push @share,@LC::State::EXPORT;
    push @share,@LC::Config::EXPORT;
    push @share,@LC::Event::EXPORT;
    push @share,@LC::Extend::EXPORT;
    push @share,@LC::StatusLine::EXPORT;
    push @share,@LC::SubClient::EXPORT;

    $safe->share(@share);
    # This only works in perl 5.003_07+
    $safe->share_from('main', [ qw($TL_VERSION %ENV %INC @INC $@ $load_ui $] $$) ]);
        
    my $old = $Extensions{/current/};
    $Extensions{$name} = { File => $filename,
			   Commands => [],
			   ShortHelp => [],
			   LongHelp => [],
			   EventHandlers => [],
			   UICallbacks => [],
			   Safe => $safe };
    $Extensions{/current/} = $Extensions{$name};

    $safe->rdo($filename);
    $Extensions{/current/} = $old;

    if ($@) {
      ui_output("* error: $@");
      extension_unload($name);
    }
}


# Unload an extension.
sub extension_unload($) {
    my($name) = @_;

    if (!defined $Extensions{$name}) {
       ui_output("(extension \"$name\" is not loaded)");
       return; 
    }
    
    ui_output("(unloading \"$name\")");

    my $old = $Extensions{/current/};
    my $ext = $Extensions{$name};
    $Extensions{/current/} = $ext;

    $ext->{Safe}->reval("unload();");

    my $x;
    @a = (@{$ext->{Commands}});
    foreach $x (@a) {
	deregister_user_command_handler($x);
    }

    @a = (@{$ext->{ShortHelp}});
    foreach $x (@a) {
	deregister_help_short($x);
    }

    @a = (@{$ext->{LongHelp}});
    foreach $x (@a) {
	deregister_help_long($x);
    }

    @a = (@{$ext->{EventHandlers}});
    foreach $x (@a) {
	deregister_handler($x);
    }

    @a = (@{$ext->{StatusLines}});
    foreach $x (@a) {
	deregister_statusline($x);
    }
    redraw_statusline();

    @a = (@{$ext->{UICallbacks}});
    foreach $x (@a) {
	ui_remove_callback($x->[0], $x->[1]);
    }

    $Extensions{/current/} = $old;
    delete $Extensions{$name};
}


# Snarf extensions out of standard locations.
sub load_extensions() {
    my $ext;
    foreach $ext (@{$config{load}}) {
	extension($ext);
    }   

    extension_cmd("list");
}


sub extension_cmd($) {
    my($args) = @_;
    my @argv = split /\s+/, $args;

    my $cmd = shift @argv;

    if ($cmd eq 'load') {
	my $ext;
	foreach $ext (@argv) {
	    extension($ext,1);
	}
    } elsif ($cmd eq 'unload') {
	my $ext;
	foreach $ext (@argv) {
	    extension_unload($ext);
	}
    } elsif ($cmd eq 'reload') {
	my $ext;
	foreach $ext (@argv) {
	    extension_unload($ext);
	    if (defined $Extensions{$ext}) {
	        my $f = $Extensions{$ext}->{File};
	        extension($f,1);
	    } else {
		extension($ext,1);
	    }
	}
    } elsif ($cmd eq 'list') {
	my $s = "(Loaded extensions:";
	foreach (sort keys %Extensions) {
	    next if ($_ eq "/current/");
	    $s .= ' ' . $_;
	}
	$s .= ")";
	ui_output($s);
    } else {
	ui_output("(unknown %extension command.  see %help extension)");
    }
}

if ($main::load_ui) {
  LC::User::register_user_command_handler('extension', \&extension_cmd);
  LC::User::register_help_short('extension', "manage tlily extensions");
  LC::User::register_help_long('extension', "
usage: %extension list
       %extension load <extension>
       %extension unload <extension>
       %extension reload <extension>
");
}




####################################################################

sub list_remove(\@$) {
    my($l,$i) = @_;
    @$l = grep { $_ ne $i } @$l;
}

sub register_eventhandler(%) {
    my(%h) = @_;
    my $id = &LC::Event::register_eventhandler(%h);
    push @{$Extensions{/current/}->{EventHandlers}}, $id;
    return $id;
}

sub register_iohandler(%) {
    my(%h) = @_;
    my $id = &LC::Event::register_iohandler(%h);
    push @{$Extensions{/current/}->{EventHandlers}}, $id;
    return $id;
}

sub register_timedhandler(%) {
    my(%h) = @_;
    my $id = &LC::Event::register_timedhandler(%h);
    push @{$Extensions{/current/}->{EventHandlers}}, $id;
    return $id;
}

sub deregister_handler($) {
    my($id) = @_;
    &LC::Event::deregister_handler($id);
    list_remove @{$Extensions{/current/}->{EventHandlers}}, $id;
}


BEGIN {
    if ($main::load_ui) {
	sub register_statusline {
	    my(%h) = @_;
	    my $id = &LC::StatusLine::register_statusline(%h);
	    push @{$Extensions{/current/}->{StatusLines}}, $id;
	    redraw_statusline();
	    return $id;
	}

        sub deregister_statusline {
	    my($id) = @_;
	    &LC::StatusLine::deregister_statusline($id);
	    list_remove @{$Extensions{/current/}->{StatusLines}}, $id;
	}

        sub redraw_statusline {
	    &LC::StatusLine::redraw_statusline(@_);
	}

	sub register_user_command_handler($&) {
	    my($cmd, $fn) = @_;
	    &LC::User::register_user_command_handler($cmd, $fn);
	    push @{$Extensions{/current/}->{Commands}}, $cmd;
	}

        sub deregister_user_command_handler($) {
	    my($cmd) = @_;
	    &LC::User::deregister_user_command_handler($cmd);
	    list_remove @{$Extensions{/current/}->{Commands}}, $cmd;
	}

        sub register_help_short {
	    my($cmd, $help) = @_;
	    &LC::User::register_help_short($cmd, $help);
	    push @{$Extensions{/current/}->{ShortHelp}}, $cmd;
	}

        sub deregister_help_short {
	    my($cmd) = @_;
	    &LC::User::deregister_help_short($cmd); 
	    list_remove @{$Extensions{/current/}->{ShortHelp}}, $cmd;
	}

        sub register_help_long {
	    my($cmd, $help) = @_;
	    &LC::User::register_help_long($cmd, $help);
	    push @{$Extensions{/current/}->{LongHelp}}, $cmd;
	}

        sub deregister_help_long {
	    my($cmd) = @_;
	    &LC::User::deregister_help_long($cmd); 
	    list_remove @{$Extensions{/current/}->{LongHelp}}, $cmd;
	}

        sub ui_callback {
	    my($key, $cmd) = @_;
	    &LC::UI::ui_callback($key, $cmd); 
	    push @{$Extensions{/current/}->{UICallbacks}}, [ $key, $cmd ];
	}

        sub ui_remove_callback {
	    my($key, $cmd) = @_;
	    &LC::UI::ui_remove_callback($key, $cmd); 
	    my $l = $Extensions{/current/}->{UICallbacks};
	    @$l = grep { ($_->[0] ne $key) || ($_->[1] ne $cmd) } @$l;
	}
    }
}

1;
