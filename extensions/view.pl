# -*- Perl -*-
# $Header: /data/cvs/tlily/extensions/view.pl,v 2.1 1998/06/12 08:57:03 albert Exp $
#To: tigerlily@hitchhiker.org
#Subject: My %view extension
#Date: Wed, 10 Dec 1997 01:09:58 PST
#From: Paul Stewart <stewart@parc.xerox.com>
#
#This allows you to get the output of a command into a temporary
#buffer for leisurely perusal or perhaps a quick search or two.  My
#general mode of use is "%view /review ...", and then perhaps doing
#a save out of the editor window that appears.
#
#--
#Paul


sub view_display(\@) {
    my($lref) = @_;
    
    my $tmpfile = "/tmp/tlily.$$";
    my $EDITOR = $ENV{VISUAL} || $ENV{EDITOR} || "vi";

    unlink($tmpfile);

    my $fh = IO::File->new(">$tmpfile");
    foreach (@$lref) {
       chomp;
       $fh->print("$_\n");
    }
    $fh->close();

    ui_end();
    system("$EDITOR $tmpfile");
    ui_start();

    unlink($tmpfile);
}

sub view_cmd($;$$) {
    my ($cmd,$filter,$doneproc) = @_;

    my @lines = ();
    cmd_process($cmd, sub {
	my($event) = @_;
	$event->{ToUser} = 0;
	if ($event->{Type} eq 'endcmd') {
            if ($doneproc) {
                &{$doneproc}(@lines);
            } else {
	        view_display(@lines);
            }
	} elsif ( $event->{Type} ne 'begincmd' &&
                  ( ! $filter || &{$filter}($event->{Raw}) ) ) {
	    $event->{Raw}=~s/^\n//g;
	    push @lines, $event->{Raw};
	}
	return 0;
    });
}


register_user_command_handler('view', \&view_cmd);
register_help_short('view', 'sends output of lily command to an editor');
register_help_long('view',
"This allows you to get the output of a command into a temporary buffer
and loads an editor to allow you to save it to a file or perhaps do a quick
search or two.  For example, you can do a \"%view /review detach\", and then
save your detach buffer, so you can respond to real-time messages, while still
keeping an eye on the past in another window.");

1;
