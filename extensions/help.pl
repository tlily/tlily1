register_user_command_handler('help', \&help_cmd);
register_help_short('help', "help on commands");
register_help_long('help', 
"It would appear that you have found the help command :)
 usage: %help
        %help [topic]");

sub help_cmd {
    my($args)=@_;

    my @topics=&help_get_list();
    my $w=0;
    foreach $topic (@topics) { 
	$t=$topic; $t=~s/^\%//g;
	$helpon{$t}=1;
	if (length($topic) > $w) { $w=length($topic); }
    }

    if ($args =~ /^\s*$/) {
	ui_output("? This is TigerLily version $TL_VERSION");
	ui_output("? Help is available on the following topics:");

	foreach $topic (@topics) {	    
	    my $s=sprintf("?  <yellow>%-$w.$w" . "s</yellow>",$topic);
	    my $t=help_get_short($topic);
	    if ($t) { $s .= " - $t";}
	    ui_output($s);
	}	
	
	ui_output("? For further help, type \'%help [topic]\'");
	return;	   
    }
    
    $args=~s/^[\%\s]*//g;

    if ($helpon{$args}) {
	ui_output("? Help on \'$args\'");
	my $f=0;
	if (help_get_short($args)) {
	    ui_output(Text => "? $args: " . help_get_short($args),
		      WrapChar => '? ');
	    $f=1;
	}
	my $longtxt= "? " . help_get_long($args);	
	$longtxt=~s/\n/\n\* /g;
	if ($longtxt) { 
	    ui_output(Text => $longtxt, WrapChar => '? '); $f=1;
	}
	if (! $f) { 
	    ui_output("? No further help for \'$args\'.  Feel like writing it?"); }
    } else {
	ui_output("? No help for \'$args\'");
    }

}




1;
