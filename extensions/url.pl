# $Header: /data/cvs/tlily/extensions/url.pl,v 2.5 1998/11/04 22:06:57 neild Exp $
#
# URL handling
#

my @urls = ();

sub handler {
    my($event, $handler) = @_;

    my $type;
    foreach $type ('http', 'https', 'ftp') {
        $event->{Body} =~ s|($type://\S+[^\s\(\)\[\]\{\}\"\'\?\,\;\:\.])|
            push @urls, $1;
            my $t=$config{tag_urls}?'['.scalar(@urls).']':"";
            "<url>$1$t</url>";|ge;
    }
    return 0;
}

sub url_cmd {
    ($arg,$num)=split /\s+/, "@_";
    my $url;

    $arg = "show" if ($arg eq "view");
    
    if ($arg eq "clear") {
       ui_output("(cleared URL list)");
       @urls=();
       return;
    }

    if ($arg eq "show" || $arg=~ /^-?\d+$/) {  
	if ($arg eq "show" && ! $num) {
	    $num=$#urls+1;
	}
	if ($arg=~/^-?\d+$/) { $num=$arg;	}	
	if (! defined $num) { 
	    ui_output("(usage: %url show <number|url> or %url show or %url <number>"); 
            return;
	}
	if ($num=~/^-?\d+$/) {
	    if ($num > @urls || $num < -@urls) {
		ui_output("(invalid URL number $num)"); return;
	    }
            if ($num > 0) { $url=$urls[$num-1]; }
            elsif ($num == 0) { $url=$urls[$#urls]; }
            elsif ($num < 0) { $url=$urls[$#urls+$num+1]; }
        } else {
	    $url = $num;
	}

	$url =~ s/([,"'])/sprintf "%%%02x", ord($1)/eg;

	ui_output("(viewing $url)");
	my $cmd=$config{browser};
	if ($cmd =~ /%URL%/) {
	    $cmd=~s/%URL%/$url/g;
	} else {
	    $cmd .= " $url";
	}
	if ($config{browser_textmode}) {
	    ui_end();
	    $ret=`$cmd 2>&1`;	    
	    ui_start();	    
	    ui_output($ret) if $ret;
	} else {
  	    $ret=`$cmd 2>&1`;
	    ui_output($ret) if $ret;
	}
	return
    }

    if (@urls == 0) {
	ui_output("(no URLs captured this session)");
	return;
    }
    ui_output("| URLs captured this session:");
    foreach (0..$#urls) {
	ui_output(sprintf("| %2d) $urls[$_]",$_+1));
    }    
}

register_eventhandler(Type => 'send', Call => \&handler);
register_user_command_handler('url', \&url_cmd);
register_help_short('url', "View list of captured urls");
register_help_long('url', "
Usage: %url
       %url clear
       %url show <num> | <url>
       %url show  (will show last url)
       %url <num>
");


