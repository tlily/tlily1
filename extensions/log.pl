# -*- Perl -*-

#
# Log a lily session to a file.
#

my $log_file;
my $log_fd;

sub log_handler($$) {
    my($event,$handler) = @_;
    if ($log_file) {
	my $text = $event->{Text};
	if ($text =~ /^%command \[\d+\] /) {
	    $text = $';
	}
	if ($text =~ /^%g/) {
	    $text = $';
	}
	if ($text !~ /^%/) {
	    $log_fd->print($text, "\n");
	}
    }

    return 0;
}

sub log_start($) {
    my($file) = @_;

    log_stop();

    $log_fd = IO::File->new(">>$file");
    if (!defined $log_fd) {
	return;
	ui_output("(Can't write to \"$file\": $!)");
    }
    $log_fd->autoflush(1);

    $log_file = $file;
    ui_output("(Now logging to \"$file\")");
}

sub log_stop() {
    if ($log_file) {
	$log_fd->close();
	ui_output("(No longer logging to \"$log_file\")");
	undef $log_file;
	undef $log_fd;
    }
}

sub log_cmd($) {
    my($file) = @_;

    if ($file eq '') {
	if ($log_file) {
	    ui_output("(Currently logging to \"$log_file\")");
	} else {
	    ui_output("(Logging is not enabled)");
	}
	return;
    }

    if ($file eq 'off') {
	if ($log_file) {
	    log_stop();
	} else {
	    ui_output("(Logging was not enabled)");
	}
    } else {
	log_start($file);
    }
    return;
}

sub unload() {
    if ($log_fd) {
	$log_fd->close();
	ui_output("(No longer logging to \"$log_file\")");
    }
}

register_eventhandler(Type => 'serverline',
		      Order => 'after',
		      Call => \&log_handler);
register_user_command_handler('log', \&log_cmd);
register_help_short('log', "Log lily session to a file");
register_help_long('log',
"usage: %log [file]
       %log off");
