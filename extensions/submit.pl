# -*- Perl -*-
# $Header: /data/cvs/tlily/extensions/submit.pl,v 1.1 1999/02/02 07:46:41 mjr Exp $

use LC::Version;

# Issue report template
$template = 
"From:
To: tigerlily-bugs\@einstein.org
Subject:
Date:

Full_Name:
Lily_Core:
Lily_Server:
tlily_Version: $TL_VERSION
OS:

Description:
";

sub submit_cmd($) {
	my($submit_to,$recover)=split /\s+/, "@_";

	if (defined($recover) && $recover ne "-r") {
		ui_output("Usage: %submit {server|client} [-r]");
		return;
	}
	$recover = ($recover eq "-r")?1:0;

	if ($submit_to =~ /^server$/) {
		ui_output("(Sorry, %submit server not yet implemented - Feel Free(TM))");
		return;
	} elsif ($submit_to =~ "client") {
	

		# Get the version of the lily core we're on.
		cmd_process("/display version", sub {
			my($event) = @_;
			$event->{ToUser} = 0;
			if ($event->{Text} =~ /^\((.*)\)/) {
				$version = $1;
			} elsif ($event->{Type} eq 'endcmd') {
				edit_report(version=>$version, recover=>$recover);
			}
			return 0;
		});
	} else {
		ui_output("Usage: %submit {server|client} [-r]");
		return;
	}
}

sub edit_report(%) {
	my %args=@_;

	my $form = $template;

	my $tmpfile = "/tmp/tlily.submit.$$";

	if ($args{'recover'}) {
		ui_output("(Recalling saved report)");
		my $rc = open(FH, "<$tmpfile");
		unless ($rc) {
			ui_output("(edit buffer file not found)");
			return;
		}
	    $form = join("",<FH>);
		close FH;
	}

	$form =~ s/^Lily_Core:$/Lily_Core: $args{'version'}/m;
	$form =~ s/^Lily_Server:$/Lily_Server: $config{'server'}:$config{'port'}/m;
	my $OS = `uname -a`;
	chomp $OS;
	$form =~ s/^OS:$/OS: $OS/m;
	my @pw = getpwuid $<;
	$pw[6] =~ s/,.*$//;
	$form =~ s/^From:$/From: $pw[0]/m;
	$form =~ s/^Full_Name:$/Full_Name: $pw[6]/m;
	my $date = gmtime() . " GMT";
	$form =~ s/^Date:.*$/Date: $date/m;
	local(*FH);
	my $mtime = 0;
	
	unlink($tmpfile);
	open(FH, ">$tmpfile") or die "$tmpfile: $!";
	print FH "$form";
	$mtime = (stat FH)[10];
	close FH;

	ui_end();
	system("$config{editor} $tmpfile");
	ui_start();

	my $rc = open(FH, "<$tmpfile");
	unless ($rc) {
		ui_output("(edit buffer file not found)");
		return;
	}

	if ((stat FH)[10] == $mtime) {
		ui_output("(report not submitted)");
		close FH;
		unlink($tmpfile);
		return;
	}

	my @data = <FH>;
	close FH;
	$form = join("",@data);
	if ($form =~ /Description:$/) {
		ui_output("(No description - report not submitted; please re-edit with %submit -r)");
		return;
	}
	if ($form =~ /^Subject:$/m) {
		ui_output("(No subject - report not submitted; please re-edit with %submit -r)");
		return;
	}


	open(FH, "|/usr/lib/sendmail -oi tigerlily-bugs\@einstein.org");
	print FH $form;
	close FH;

	unlink($tmpfile);

	ui_output("(Report submitted)");
}


register_user_command_handler('submit', \&submit_cmd);

register_help_short("submit", "Submit a bug report");
register_help_long("submit",  <<END
Usage: %submit client [-r]
       %submit server [-r]

Submits a bug report, either for the server or for the client (Tigerlily).
Will start your editor with a form for you to fill out.  Will automatically
retrieve basic information about your environment (versions, OS, etc), and
put that in the form, too.
If for some reason it isn't able submit your report, you can recover the
report with the -r option.
END
);


1;
