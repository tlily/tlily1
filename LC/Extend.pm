# -*- Perl -*-
package LC::Extend;

use Exporter;
use Safe;
use LC::UI;
use LC::Server;
use LC::parse;
use LC::User;
use LC::Command;
use LC::State;
use LC::log;
use LC::config;
use LC::Event;

@ISA = qw(Exporter);

@EXPORT = qw(&extension
	     &load_extensions);

# initial version, 10/24/97, Josh Wilmes

# Provide a secure environment for user extensions to TigerLily.  We use
# a Safe to provide strict control over what the extensions have access to.


my %Extensions = ();
my @loading_exts = ();


sub extension($) {
    my ($filename)=@_;
    my @share=();

    my $safe=new Safe;

    my $name = $filename;
    $name =~ s|^.*/||; $name =~ s|\.pl$||;

    return if (defined $Extensions{$name});

    ui_output("*** loading \'$name\' extension");

    # Since security isnt a primary concern, I allow all perl operators to be
    # used.
    # note that due to changes in the safe module in 5.002 vs newer versions,
    # and my lack of an old version to test on, things might not quite work
    # on older perls.
    if ($Safe::VERSION >= 2) {
	$safe->deny_only("system");
	$safe->permit("system");
    } else {
	$safe->mask($safe->emptymask());
    }

    push @share,@LC::UI::EXPORT;
    push @share,@LC::Server::EXPORT;
    push @share,@LC::parse::EXPORT;
    push @share,@LC::User::EXPORT;
    push @share,@LC::Command::EXPORT;
    push @share,@LC::State::EXPORT;
    push @share,@LC::log::EXPORT;
    push @share,@LC::config::EXPORT;
    push @share,@LC::Event::EXPORT;
    $TL_VERSION=$main::TL_VERSION;
    push @share,qw($TL_VERSION);
    
    $safe->share (@share);
        
    my $old = $Extensions{/current/};
    $Extensions{$name} = { File => $filename,
			   Commands => [],
			   ShortHelp => [],
			   LongHelp => [],
			   EventHandlers => [],
			   Safe => $safe };
    $Extensions{/current/} = $Extensions{$name};

    $safe->rdo($filename);
    ui_output("* error: $@") if $@;

    $Extensions{/current/} = $old;
}


# Unload an extension.
sub extension_unload($) {
    my($name) = @_;

    return if (!defined $Extensions{$name});

    ui_output("*** unloading \'$name\' extension");

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
	deregister_eventhandler($x);
    }

    $Extensions{/current/} = $old;
    delete $Extensions{$name};
}


# Snarf extensions out of standard locations.
sub load_extensions() {
    ui_output("(Searching ~/.lily/tlily/extensions for extensions)");
    foreach (grep /[^~]$/, glob "$ENV{HOME}/.lily/tlily/extensions/*.pl") {
	extension($_);
    }   

    ui_output("(Searching " . $main::TL_EXTDIR . " for extensions)");
    foreach (grep /[^~]$/, glob $main::TL_EXTDIR."/*.pl") {
	extension($_);
    }   
}


sub extension_cmd($) {
    my($args) = @_;
    my @argv = split /\s+/, $args;

    my $cmd = shift @argv;

    if ($cmd eq 'info') {
	my $ext;
	foreach $ext (@argv) {
	    if (!defined $Extensions{$ext}) {
		ui_output("(No such extension: \"$ext\")");
		next;
	    }

	    my $s;
	    ui_output("Extension: $ext");

	    $s = "Commands: ";
	    foreach (@{$Extensions{$ext}->{Commands}}) { $s .= ' '.$_; }
	    ui_output($s);

	    $s = "ShortHelp:";
	    foreach (@{$Extensions{$ext}->{ShortHelp}}) { $s .= ' '.$_; }
	    ui_output($s);

	    $s = "LongHelp: ";
	    foreach (@{$Extensions{$ext}->{LongHelp}}) { $s .= ' '.$_; }
	    ui_output($s);

	    $s = "Handlers: ";
	    foreach (@{$Extensions{$ext}->{EventHandlers}}) { $s .= ' '.$_; }
	    ui_output($s);
	}
	return 0;
    } elsif ($cmd eq 'load') {
	my $ext;
	foreach $ext (@argv) {
	    extension($ext);
	}
    } elsif ($cmd eq 'unload') {
	my $ext;
	foreach $ext (@argv) {
	    extension_unload($ext);
	}
    } elsif ($cmd eq 'reload') {
	my $ext;
	foreach $ext (@argv) {
	    my $f = $Extensions{$ext}->{File};
	    extension_unload($ext);
	    extension($f);
	}
    } elsif ($cmd eq 'list') {
	my $s = "(Loaded extensions:";
	foreach (sort keys %Extensions) {
	    next if ($_ eq "/current/");
	    $s .= ' ' . $_;
	}
	$s .= ")";
	ui_output($s);
    }
}

LC::User::register_user_command_handler('extension', \&extension_cmd);


####################################################################

sub list_remove(\@$) {
    my($l,$i) = @_;
    @$l = grep { $_ ne $i } @$l;
}

sub register_eventhandler(%) {
    my(%h) = @_;
    my $id = &LC::Event::register_eventhandler(%h);
    push @{$Extensions{/current/}->{EventHandlers}}, $id;
}

sub deregister_eventhandler($) {
    my($id) = @_;
    &LC::Event::deregister_eventhandler($id);
    list_remove @{$Extensions{/current/}->{EventHandlers}}, $id;
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

