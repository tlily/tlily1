#
# Handle autologins.
#

# List of places to look for an autologin file.
my @files = ("$ENV{HOME}/.lily/tlily/autologin",
	     "$ENV{HOME}/.lily/lclient/autologin");
unshift @files, $config{'autologin_file'} if ($config{'autologin_file'});

init() unless $config{noauto};

register_help_short("autologin", "Module for automating the login process.");
register_help_long("autologin", 
"Reads files containing lines of the format: <green>alias host port login passwd</green> in order to automate your login process to the specified server.  Unlike lclient, all fields must be present or the line will be ignored. (FIXME!)
Config options for autologin:
    \$autologin_file = '<yellow>filename</yellow>';
        Prepends <yellow>filename</yellow> to the list of filenames containing autologin information.
");

sub init {
    my $file;
    foreach $file (@files) {
	open(FD, $file) or next;
	while (<FD>) {
	    next if (/^\s*(\#.*)?$/);
	    my ($alias, $host, $port, $user, $pass) = split;
	    next unless defined($pass);

	    if ($alias eq $config{'server'}) {
		$config{'server'} = $host;
		$config{'port'}   = $port;
	    }

	    if (($host eq $config{'server'}) && ($port eq $config{'port'})) {
		register_eventhandler(Type => 'prompt',
				      Order => 'before',
				      Call => sub {
		    my($event, $handler) = @_;
		    return 0 unless ($event->{Text} =~ /^login:/);
		    ui_output("(using autologin information)");
		    server_send("${user} ${pass}\n");
		    deregister_handler($handler->{Id});
		    return 1;
		});
		
		last;
	    }
	}
	close(FD);

	last;
    }
}
