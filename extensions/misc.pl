register_eventhandler(Type => 'uunknown',
		      Call => \&bang_handler);
register_help_short('eval', "run perl code");
register_help_long('eval', "usage: eval <perl code>");
register_help_short('!', "run shell command");
register_help_long('!', "usage: ! <command>");

register_user_command_handler('version', \&version_handler);
register_help_short('version', "Display the version of Tigerlily and the server");
register_help_long('version', "usage: %version\n* Displays the version of Tigerlily and the server.\n");


register_user_command_handler('echo', \&echo_handler);
register_help_short('echo', "Echo text to the screen.");


# %eval handler
sub eval_handler($) {
    my($args) = @_;
    my $rc = eval($args);
    ui_output("* Error: $@") if ($@);
    ui_output("-> $rc") if (defined $rc);
}
register_user_command_handler('eval', \&eval_handler);

# %set handler
sub set_handler($) {
    my($args) = @_;
    if($args =~ m/^([\w\-_]+)\{?([\w_]+)?\}?\s*=\s*([\w_\-:]+)\s*$/) {
	my($var,$key,$val) = ($1,$2,$3);
	if($key) {
	    if(!defined($config{$var}) || (ref($config{$var}) eq 'HASH' && ref($config{$var}{$key}) eq '')) {
		$config{$var}{$key} = $val;
	    } else { ui_output("(Invalid type for variable)"); }
	}
	else {
	    if(ref($config{$var}) eq '') {
		$config{$var} = $val;
	    } else { ui_output("(Invalid type for variable)"); }
	}
    }
    elsif($args =~ m/^([\w\-_]+)\{?([\w_]+)?\}?\s*=\s*\(([\w_\-:,]+)\)\s*$/) {
	my($var,$key,$val) = ($1,$2,$3);
	my @L = split(/\s*,\s*/, $val);
	if($key) {
	    if(!defined($config{$var}) || !defined($config{$var}{$key}) || (ref($config{$var}) eq 'HASH' && ref($config{$var}{$key}) eq 'ARRAY')) {
		$config{$var}{$key} = \@L;
	    } else { ui_output("(Invalid type for variable)"); }
	}
	else {
	    if(!defined($config{$var})) {
		$config{$var} = [ @L ];
	    } elsif(!defined($config{$var}) || ref($config{$var}) eq 'ARRAY') {
		$config{$var} = [ @{$config{$var}}, @L ];
	    } else { ui_output("(Invalid type for variable)"); }
	}
    }
    elsif($args =~ m/^([\w\-_]+)\{?([\w_]+)?\}?\s*$/) {
	my($var,$key,$val) = ($1,$2,$3);
	if($key) {
	    if(ref $config{$var}->{$key} eq 'ARRAY') {
		ui_output("\$config{$var}{$key} = ".join(', ', @{$config{$var}{$key}}));
	    } else {
		ui_output("\$config{$var}{$key} = ".$config{$var}{$key});
	    }
	}
	else {
	    if(ref $config{$var} eq 'ARRAY') {
		ui_output("\$config{$var} = ".join(', ', @{$config{$var}}));
	    } else {
		ui_output("\$config{$var} = ".$config{$var});
	    }
	}
    }
    return 0;
}
register_user_command_handler('set', \&set_handler);
register_help_short('set', "Set configuration variables");
register_help_long('set', qq(usage:
    %set name=value
        Sets a scalar config variable to a value.
    %set name=(value,value,value)
        Appends the given list to a list config variable.
    %set name{key}=value
        Sets the hash hey key in the config variable name to value.
    %set name{key}=(value,value,value)
        Sets the hash hey key in the config variable name to the given list.
  Examples:
    %set mono=1
        Turns on monochrome mode.  (Also has the side effect of setting your
        colors to your monochrome preferences.)
    %set slash=(also,oops)
        Appends 'also', and 'oops' onto your list of /-commands that
        are allowed to be intercepted.
    %set color_attrs{pubmsg}=(normal,bg:red,fg:green,bold)
        Sets your color pref. for public messages to black on white & bold.
));

# !command handler
sub bang_handler($$) {
    my($event,$handler) = @_;
    if ($event->{Text} =~ /^\!(.*?)\s*$/) {
	$event->{ToServer} = 0;
	ui_output("[beginning of command output]");
	open(FD, "$1 |");
	my @r = <FD>;
	close(FD);
	foreach (@r) {
	    chomp;
	    s/([\\<])/\\$1/g;
	    ui_output($_);
	}
	ui_output("[end of command output]");
	return 1;
    }
    return 0;
}

# %version handler
sub version_handler {
    ui_output("(Tigerlily version $TL_VERSION)\n");
    server_send("/display version\r\n");
    return 0;
}

# %echo handler
sub echo_handler {
    ui_output(join(' ', @_));
    return 0;
}
