# -*- Perl -*-
package LC::SubClient;

# bugs:
# %del_hack needs to be fixed.
# bug if you del a subclient and make a new one with the same name. (locks up)
# bug if error in open3


=head1 NAME

LC::SubClient - subclient interface

=head1 SYNOPSIS

    use LC::SubClient;

    (in tigerlily)
    %subclient add <subclient name> <subclient program>
    %subclient remove <subclient name>
    %subclient list

=head1 DESCRIPTION

The SubClient module provides the ability to add "sub clients", programs whose
input and output are accessable from within tlily.

=cut

use IPC::Open3;
use POSIX ":sys_wait_h";
use IO::Select;
use LC::Event;
use LC::UI;
use LC::User;
use LC::StatusLine;

my @subcli=qw(Lily);
my (%rhandle,%whandle,%ehandle);
my (%opfx,%ipfx);
my (%color);
my $subcli_num;
$status="";

# Or else we get big WARNING:s.
$SIG{PIPE} = "IGNORE";

register_statusline(Var => \$status,
                    Position => "FORCELEFT");

$usage=ui_escape("usage:
    %subclient add <subclient name> <subclient program>
    %subclient remove <subclient name>
    %subclient list
");

register_user_command_handler('subclient', \&subclient);
register_help_short('subclient', 'run a \"sub client\"');
register_help_long('subclient', $usage);

register_user_command_handler('irc', \&irc);
register_help_short('irc', 'run dsirc as a \"sub client\"');
register_help_long('irc', ui_escape("usage:
    %irc <nick> <server>

Dsirc is a portion of the sirc irc client.  You must have sirc installed on
your system in order to use it!

http://www.eleves.ens.fr:8080/home/espel/sirc.html

"));

sub irc {
    subclient("add","irc","dsirc @_");
}


sub subclient {
    ($cmd,$subcli,@proc)=split /\s+/,"@_";
    my $proc=join ' ',@proc;

    if ($cmd eq "list") {
	if (scalar(@subcli)-1) { 
	    ui_output("The following subclients are installed:");
	    foreach (@subcli) { next if /Lily/;  ui_output(" $_"); }
	} else {
	    ui_output("(No subclients are installed.)");
	}
	return;
    } elsif ($cmd eq "add") { 
	subclient_add(@_); 
    } elsif ($cmd eq "remove" || $cmd eq "del") {
	subclient_del(@_);
    } else {
	ui_output($usage);
    }
}


sub subclient_del {
    ($cmd,$subcli)=split /\s+/,"@_";
    
    my @newsubcli;
    my $dereg=0;
    foreach (@subcli) {
	if ($_ ne $subcli) {
	    push @newsubcli,$_;
	} else {
	    $dereg++;
	    deregister_handler($rhid{$subcli});
	    deregister_handler($ehid{$subcli});
	    $rhandle{$subcli}->close;
	    $whandle{$subcli}->close;
	    $ehandle{$subcli}->close;
		 #ui_end();
	    kill "TERM",$pid{$subcli};
		 #ui_start();
# Handled now by the SIGCHLD handler
#	    waitpid($pid{$subcli},&WNOHANG);
	}
    }
    @subcli=@newsubcli;
    $subcli_num=0;
    if ($#subcli == 0) {
	$status="";
	$SIG{CHLD} = "DEFAULT";
    } else {
	$status=ui_escape("<$subcli[$subcli_num]>");
	$SIG{CHLD} = \&sig_chld_handler;
    }
    redraw_statusline(1);       

    if ($dereg) {
	ui_output("(removed subclient \"$subcli\")");
	$del_hack{$subcli}=1;
    } else {
	ui_output("(subclient \"$subcli\" not found)");
    }
}

sub subclient_add {
    ($cmd,$subcli,@proc)=split /\s+/,"@_";
    my $proc=join ' ',@proc;
	 my $pid;
    
    $opfx="$subcli>";
    $ipfx=$subcli;

    if (! $callbacks_setup) {
	$callbacks_setup=1;
	ui_callback("`",\&toggle_key);
	register_eventhandler(Type => 'userinput',
			      Order => 'before',
			      Call => \&sc_userinput_handler);
    }

    $SIG{CHLD} = \&sig_chld_handler;

    $rh=$rhandle{$subcli}=new FileHandle;
    $wh=$whandle{$subcli}=new FileHandle;
    $eh=$ehandle{$subcli}=new FileHandle;
    
    # fork off the process and hook it into tigerlily..
	 #ui_end();
    eval { $pid = open3($wh, $rh, $eh, $proc); };
	 #ui_start();
    if (! $pid) {
#	ui_output("(Error starting subclient)");
	exit;
    }

	 ui_output("(Error starting subclient: $@)") if $@;

    $ipfx{$subcli}=$ipfx;
    $opfx{$subcli}=$opfx;
	 $color{$subcli}="subc";
    push @subcli,$subcli;     
    $subcli_num++;
    $pid{$subcli}=$pid;

    ui_output("(Started process $pid ($proc) - use the \` key to switch)");

    $rhid{$subcli}=register_iohandler(Handle => $rh,
				      Mode => 'r',
				      Name => "SC$subcli",
				      Call => \&subcli_input_process);
    
    $ehid{subcli}=register_iohandler(Handle => $eh,
				     Mode => 'r',
				     Name => "SCE$subcli",
				     Call => \&subcli_input_process);

    $status=ui_escape("<$subcli>");
    redraw_statusline();       
}

sub subcli_input_process {
    my ($handler)=@_;
    my $hdl;
    if ($handler->{Name}=~/SCE/) {
	($subcli)=($handler->{Name}=~/SCE(.+)/);
	$hdl=$ehandle{$subcli};
    } else {
	($subcli)=($handler->{Name}=~/SC(.+)/);
	$hdl=$rhandle{$subcli};
    }     

    my $buf;
    my $s=new IO::Select;
    $s->add($hdl);
    if (! ($s->can_read(0))) { return; }

    my $rc = sysread($hdl,$buf,4096);
    if ($rc < 0) {
        if ($errno != EAGAIN) {
            die("sysread: $!"); 
        }
    } elsif ($rc == 0) {
	if (! $del_hack{$subcli}) {
	    $del_hack{$subcli}=1;
	    subclient_del("del",$subcli);
	}
    }

    foreach $line (split '[\n\r]',$buf) {
	next unless $line;
	# should have a user-registerable pre-filter here.. for 
	# extensions that want to define customized behaviors (dsirc 
	# springs to mind)
	ui_output("<$color{$subcli}>$opfx{$subcli}</$color{$subcli}> " .
				  ui_escape($line));
    }
}

sub toggle_key {
    my($key, $line, $pos) = @_;

    $subcli_num++;
    if ($subcli_num > $#subcli) { $subcli_num=0; }
    if ($#subcli == 0) {
	$status="";
    } else {
	$status=ui_escape("<$subcli[$subcli_num]>");
    }
    redraw_statusline(1);       

    return ($line, $pos, 0);   
}


sub sc_userinput_handler {
    my($event,$handler) = @_;
    return if $event->{Text} =~ /^\s*%/;

    if ($subcli[$subcli_num] =~ /Lily/) {
	# sending to lily, do nothing..
    } else {
	$event->{ToServer} = 0;
	my ($wh)=$whandle{$subcli[$subcli_num]};
	print $wh "$event->{Text}\n";
	return 1;
    }
    return 0;
}

sub sig_chld_handler {
    my $child;
	 my %pids = reverse %pid;

    while ($child = waitpid(-1, WNOHANG)) {
	last if (!$pids{$child});
   ui_output("(Subclient $pids{$child} terminated abnormally)")
  if ($? == WIFSIGNALED);
   subclient_del("remove", $pids{$child});
	 }
}
