# $Header: /data/cvs/tlily/extensions/set.pl,v 2.2 1998/06/23 02:02:45 mjr Exp $
sub dumpit {
    my($l,%H) = @_;
    $l = 0 if ! $l;
    while(($k,$v) = each %H) {
	if(ref($v) eq '' || ref($v) eq 'SCALAR') {
	    ui_output("\t"x$l."$k = $v");
	}
	if(ref($v) eq 'SCALAR') {
	    ui_output("\t"x$l."$k = $$v");
	}
	elsif(ref($v) eq 'ARRAY') {
	    ui_output("\t"x$l."$k = ".join(", ", @$v));
	}
	elsif(ref($v) eq 'HASH') {
	    ui_output("\t"x$l."$k = HASH");
	    dumpit($l+1,%$v);
	}
    }
}

# %show handler
sub show_handler($) {
    my($args) = @_;
    (my $name = $args) =~ /[\w\-_]/;
    dumpit(0, ($name =>$config{$name}));
    return 0;
}

# %unset handler
sub unset_handler($) {
    my($args) = @_;
    (my $name = $args) =~ /[\w\-_]/;
    delete $config{$name};
    return 0;
}

# %set handler
sub set_handler($) {
    my($args) = @_;

    $args =~ s/ /=/ if $args !~ m/=/;
    if($args eq '') {
	ui_output("Config Variables:");
	dumpit(0,%config);
	return 0;
    }

    if($args =~ m/^([\w\-_]+)\{?([\w_]+)?\}?\s*=\s*(\S+)\s*$/) {
	my($var,$key,$val) = ($1,$2,$3);
	if($key) {
	    if(!defined($config{$var}) || (ref($config{$var}) eq 'HASH' && ref($config{$var}{$key}) eq '')) {
		$config{$var}{$key} = $val;
	    	dumpit(0, $var => {$key => $config{$var}{$key}});
	    } else { ui_output("(Invalid type for variable)"); }
	}
	else {
	    if(ref($config{$var}) eq '') {
		$config{$var} = $val;
	    	dumpit(0, $var => $config{$var});
	    } else { ui_output("(Invalid type for variable)"); }
	}
    }
    elsif($args =~ m/^([\w\-_]+)\{?([\w_]+)?\}?\s*=\s*\((\S+)\)\s*$/) {
	my($var,$key,$val) = ($1,$2,$3);
	my @L = split(/\s*,\s*/, $val);
	if($key) {
	    if(!defined($config{$var}) || !defined($config{$var}{$key}) || (ref($config{$var}) eq 'HASH' && ref($config{$var}{$key}) eq 'ARRAY')) {
		$config{$var}{$key} = \@L;
	    	dumpit(0, $var => {$key => $config{$var}{$key}});
	    } else { ui_output("(Invalid type for variable)"); }
	}
	else {
	    if(!defined($config{$var})) {
		$config{$var} = [ @L ];
	    	dumpit(0, $var => $config{$var});
	    } elsif(!defined($config{$var}) || ref($config{$var}) eq 'ARRAY') {
		$config{$var} = [ @{$config{$var}}, @L ];
	    	dumpit(0, $var => $config{$var});
	    } else { ui_output("(Invalid type for variable)"); }
	}
    }
    elsif($args =~ m/^([\w\-_]+)\{?([\w_]+)?\}?\s*$/) {
	my($var,$key,$val) = ($1,$2);
	if($key) {
	    dumpit(0, $var => {$key => $config{$var}{$key}});
	}
	else {
	    dumpit(0, $var => $config{$var});
	}
    }
    else {
	ui_output("(Syntax error: see %help set for usage)");
    }
    return 0;
}

register_user_command_handler('show', \&show_handler);
register_help_short('show', "Show the value of a configuration variable");

register_user_command_handler('unset', \&unset_handler);
register_help_short('unset', "UNset a configuration variable");

register_user_command_handler('set', \&set_handler);
register_help_short('set', "Set a configuration variable");
register_help_long('set', qq(usage:
    %set name value
        Sets the scalar config variable [name] to [value].
    %set name (value,value,value)
        Appends the given list to the config variable [name].
    %set name{key} value
        Sets the hash key [key] in the config variable [name] to [value].
    %set name{key} (value,value,value)
        Sets the hash key [key] in the config variable [name] to the given list.
  Examples:
    %set mono 1
        Turns on monochrome mode.  (Also has the side effect of setting the
        colors on your screen to your monochrome preferences.)
    %set slash (also,-oops)
        Adds also and -oops to your \@slash list.  Has the side-effect of
        allowing /also to be intercepted, and disabling /oops from being
        intercepted.
    %set color_attrs{pubmsg} (normal,bg:red,fg:green,bold)
        Sets your color pref. for public messages to black on white & bold.
        (Also has the side effect of changing the color of public messages
        on your screen to those colors)
));

1;
