#!/usr/bin/perl

use Config;
use Carp;
use File::Copy;
use File::Path;
use FileHandle;
use DirHandle;
use Cwd;
use LC::version;

# You no longer have to edit the paths here to configure tigerlily.
# This build script will ask you where you want to put tigerlily
# and make a build.cache file to save your preferences.

# Find perl
$PERL = $Config{'startperl'} ||
        $Config{'perlpath'}? "#!".$Config{'perlpath'} : '' ||
        "#/usr/bin/perl";

while(@ARGV) {
	if($ARGV[0] eq "-n") {
		$nonono = 1; shift;
	}
	elsif($ARGV[0] eq "-d") {
		$debug = 1; shift;
	}
	elsif($ARGV[0] eq "-h") {
		&Usage;
	}
	elsif($ARGV[0] eq "-f") {
		$yesdamnit = 1; shift;
	}
	elsif($ARGV[0] eq "-c") {
		$current = 1; shift;
	} else {
		$target=shift;
	}
}

print "-d: $debug\n" if $debug;
print "-n: $nonono\n" if $debug;

$VERSION = $TL_VERSION;
$CVSTAG = &ver2tag($VERSION);
$STATE = 'release';
$moddir="LC";
$extdir="extensions";
$modext='\.pm';
$extext='\.pl';
@modfiles = &get_files($moddir, $modext);
@extfiles = &get_files($extdir, $extext);
print join("\n", @modfiles), "\n" if $debug;
print join("\n", @extfiles), "\n" if $debug;

if(!$target || $target eq 'tlily') {
	&make_tlily;
	if(!$DIRS_ARE_LOCAL && !$nonono) {
		print "To install Tigerlily, do a 'perl Build.PL install'.\n";
	}
}
elsif($target eq 'install') {
	&make_tlily;
	
	if($DIRS_ARE_LOCAL) {
		print "\nYour installation directories are set for local development of tigerlily.\n";
		my($inp) = &ask("Do you really want to install tigerlily?", "n");
		if($inp eq '' || $inp =~ /(n|no)/io) {
			print "OK, bailing out of install.\n";
			exit(1);
		}
		print "I hope you know what you're doing..\n";
	}
	print "Installing tlily...\n";
	&install('DIR' => $BINDIR, 'MODE' => 0755);
	&install('FILE' => 'tlily',
	         'DEST' => $BINDIR.'/tlily',
	         'MODE' => 0755);

	print "Installing tlily internal modules...\n";
	&install('DIR' => "$LIBMODDIR/$moddir", 'MODE' => 0755);

	my($file);
	foreach $file (@modfiles) {
		&install('FILE' => "$moddir/$file",
		         'DEST' => "$LIBMODDIR/$moddir/$file",
		         'MODE' => 0644);
	}

	print "Installing tlily global extensions...\n";
	&install('DIR' => $LIBEXTDIR, 'MODE' => 0755);

	foreach $file (@extfiles) {
		&install('FILE' => "$extdir/$file",
		         'DEST' => "$LIBEXTDIR/$file",
		         'MODE' => 0644);
	}
}
elsif($target eq 'release') {
	my($cmd);

	$VERSION = &next_version($VERSION);
	&ask_version;
	&make_version_file($VERSION);
	
	$cmd = "cvs commit -m 'Automatic commit of version file' LC/version.pm";
	if($nonono) {
		print "Would have executed: $cmd\n";
	}
	else {
		print "Committing LC/version.pm with:\n$cmd\n";
		$rc = system($cmd);
		if($rc) { die "Command returned error!\n"; }
	}

	$cmd = "cvs tag -F $CVSTAG";
	if($nonono) {
		print "Would have executed: $cmd\n";
	}
	else {
		print "Tagging release $VERSION with:\n$cmd\n";
		$rc = system("$cmd");
		if($rc) { die "Command returned error!\n"; }
	}

	if($nonono) {
		print "Would have created directory 'buildtmp'\n";
		print "Would have changed directory to 'buildtmp'\n";
	}
	else {
		print "Making temporary release directory..\n";
		mkdir("buildtmp", 0755);
		chdir("buildtmp");
	}

	$cmd = "cvs export -r $CVSTAG -d tlily-$VERSION tlily";
	if($nonono) {
		print "Would have executed: $cmd\n";
	}
	else {
		print "Exporting tlily $VERSION with:\n$cmd\n";
		$rc = system("$cmd");
		if($rc) { die "Command returned error!\n"; }
	}

	$cmd = $Config{'tar'} || "tar";
	$cmd .= " cf ../tlily-$VERSION.tar tlily-$VERSION";
	if($nonono) {
		print "Would have executed: $cmd\n";
	}
	else {
		if(-f "../tlily-$VERSION.tar") { unlink("../tlily-$VERSION.tar"); }
		print "Packaging tlily $VERSION with:\n$cmd\n";
		$rc = system("$cmd");
		if($rc) { die "Command returned error!\n"; }
	}

	if($nonono) {
		print "Would have changed directory to ..\n";
		print "Would have removed directory 'buildtmp'\n";
	}
	else {
		chdir("..");
		print "Removing temporary release directory..\n";
		rmtree("buildtmp", 0, 0);
	}

	$cmd = $Config{'gzip'} || "gzip";
	$cmd .= " -9 tlily-$VERSION.tar";
	if($nonono) {
		print "Would have executed: $cmd\n";
	}
	else {
		if(-f "tlily-$VERSION.tar.gz") { unlink("tlily-$VERSION.tar.gz"); }
		print "Compressing the release archive with:\n$cmd\n";
		$rc = system("$cmd");
		if($rc) { die "Command returned error!\n"; }
	}

}
elsif($target eq 'clean') {
	rmtree('buildtmp', 0, 0);
	unlink("tlily");
	unlink("tlily-$VERSION.tar");
	unlink("tlily-$VERSION.tar.gz");
	unlink("build.cache");
}
else {
	print STDERR "Unknown target $target\n";
	&Usage;
}
	

exit(0);

sub get_files {
	my($dir,$ext) = @_;
	my($dh) = new DirHandle($dir);
	die $! if not $dh;

	grep { /${ext}$/ && -f "${dir}/$_" } readdir($dh);
}

sub install {
	my(%p) = @_;
	my($file, $dest, $dir, $mode, $rc);

	$file ||= $p{'FILE'};
	$dest ||= $p{'DEST'};
	$dir ||= $p{'DIR'};
	$mode ||= $p{'MODE'};

	if(defined($dir)) {
		$mode ||= 0755;
		if($nonono) {
			print "Would have made directory ", $dir, ", mode ";
			printf("%o\n", $mode);
		}
		else {
			if(! -e $dir) {
				$rc = mkpath($dir, 0, $mode); 
				if(!$rc) { croak $dir,": ",$!; }
			}
			chmod($mode,$dir);
		}
		return 1;
	}
	elsif(defined($file) && defined($dest)) {
		$mode ||= 0644;
		if($nonono) {
			print "Would have copied $file to ", $dest, ", mode ";
			printf("%o\n", $mode);
		}
		else {
			$rc = copy($file, $dest);
			if(!$rc) { croak $file,": ",$!; }

			$rc = chmod($mode, $dest);
			if(!$rc) { croak $dest,": ",$!; }
		}
	}
	else {
		croak "Bad args to install()";
	}
}

sub make_tlily {
	&ask_dirs;
	if($nonono) {
		print "Would have created tlily from tlily.PL with the following\n";
		print "parameters:";
		print qq(
               To start Perl:  $PERL
           TigerLily version:  $VERSION
    Module Library directory:  $LIBMODDIR
Extensions Library directory:  $LIBEXTDIR
);
		return;
	}
	print "Writing tlily\n";
	if(-f 'tlily') {
		unlink 'tlily';
	}
	my($ifh) = new FileHandle("tlily.PL", "r");
	die $! if not $ifh;

	my($ofh) = new FileHandle("tlily", "w");
	if(!$ofh) {
		my($msg) = $!; close($ifh); die $msg;
	}

	while(<$ifh>) {
		s|\@\@PERL\@\@|$PERL|;
		s|\@\@LIBMODDIR\@\@|$LIBMODDIR|;
		s|\@\@LIBEXTDIR\@\@|$LIBEXTDIR|;
		print $ofh $_;
	}
	close($ifh);
	close($ofh);
	chmod(0555, "tlily");
}

sub Usage {
	print qq(
Usage: perl Build.PL [-n][-h][install|release]
	-n: Show what would have been done without actually doing it.
	-h: Show this help
	install: do path substitutions on tlily.PL and install TigerLily
	release: tag the release via CVS and make a .tar.gz for release
	clean:   remove the generated tlily and any left-over files and
	         directories possibly left behind by this script.
);
	exit(1);
}

sub ask_dirs {
	my($inp);
	my($cachefile) = "build.cache";

	if(-f $cachefile) {
		print "Reading cache file $cachefile.\n";
		do "$cachefile";
		if($DIRS_ARE_LOCAL) {
			print "\n*** It is recommended that you NOT do 'perl Build.PL install' ***\n\n";
		}
		return;
	} elsif($current == 1) {
		&use_current_dir; return;
	} else {
		$PREFIX='/usr/local';
		print qq(By default, tlily will be installed in $PREFIX/bin, global extensions
under $PREFIX/lib/tlily/extensions, etc..., i.e. with
$PREFIX as prefix for all installation directories.  It is typically
set to /usr/local, but you may choose /usr if you wish to install
tlily among your system binaries.  If you wish to have binaries under
/bin but support files under /usr/local/lib, that's ok: you will be
prompted separately for each of the installation directories, the
prefix only used to set the defaults.

Use an installation prefix of 'Current' to configure tlily for use in
the current directory only.

);

		$inp = &ask("Installation prefix to use?", $PREFIX);
		if($inp) {
			if($inp eq 'Current') {
				&use_current_dir; return;
			}
			$PREFIX=&tilde_expand($inp);
		}
	
		$BINDIR=$PREFIX."/bin";
		$inp = &ask("\nInstallation directory for the tlily script?", $BINDIR);
		if($inp) { $BINDIR=&tilde_expand($inp); }
		
		$LIBDIR=$PREFIX."/lib/tlily";
	
		$LIBMODDIR=$LIBDIR; # the LC dir will be made below this
		print "\nInstallation directory for the tlily internal modules?  (The directory 'LC'\n";
		$inp = &ask("will be created under this directory for the internal modules.)", $LIBMODDIR);
		if($inp) { $LIBMODDIR=&tilde_expand($inp); }
	
		$LIBEXTDIR=$LIBDIR."/extensions";
		$inp = &ask("\nInstallation directory for the tlily global extensions?",
		    $LIBEXTDIR);
		if($inp) { $LIBEXTDIR=&tilde_expand($inp); }
		$DIRS_ARE_LOCAL = '0';

		&write_buildcache;
	}
}

sub use_current_dir {
	print "\nUsing current directory.\n";
	$PREFIX = Cwd::cwd;
	print "Installation prefix is $PREFIX\n";
	$BINDIR = $PREFIX;
	print "Script location is $BINDIR\n";
	$LIBDIR = $PREFIX;
	$LIBMODDIR = $LIBDIR;
	print "Module location is $LIBMODDIR\n";
	$LIBEXTDIR = $LIBDIR."/extensions";
	print "Extension directory is $LIBEXTDIR\n";
	$DIRS_ARE_LOCAL = 1;

	print "\n*** It is recommended that you NOT do 'perl Build.PL install' ***\n\n";

	&write_buildcache;
}

sub write_buildcache {
		my($cachefile) = 'build.cache';
		if($nonono) {
			print "Would have written $cachefile with the following\n";
			print "settings:\n";
			print "\$PREFIX = '$PREFIX'\n";
			print "\$BINDIR = '$BINDIR'\n";
			print "\$LIBDIR = '$LIBDIR'\n";
			print "\$LIBMODDIR = '$LIBMODDIR'\n";
			print "\$LIBEXTDIR = '$LIBEXTDIR'\n";
			print "\$DIRS_ARE_LOCAL = '$DIRS_ARE_LOCAL'\n";
			return;
		}
		print "Writing $cachefile\n";
		if(-f $cachefile) { unlink $cachefile; }
		my($fh) = new FileHandle($cachefile, "w");
		if(!$fh) { die $!; }

		print $fh qq(# build.cache
# Automatically generated by Build.PL.
\$PREFIX = '$PREFIX';
\$BINDIR = '$BINDIR';
\$LIBDIR = '$LIBDIR';
\$LIBMODDIR = '$LIBMODDIR';
\$LIBEXTDIR = '$LIBEXTDIR';
\$DIRS_ARE_LOCAL = '$DIRS_ARE_LOCAL';
);
		close $fh;
		chmod(0444, $cachefile);
}

sub ask_version {
	my($ver) = $VERSION;
	my($inp) = &ask("Release Version?", $ver);

	if($inp ne '') {
		$inp = version_part($inp);
		if(!$inp) { die "bad version string"; }
		$VERSION = $inp;
	}
	else {
		$VERSION=$ver;
	}
	$CVSTAG = &ver2tag($VERSION);
	print "VERSION=$VERSION\nCVSTAG=$CVSTAG\n" if $debug;
}

sub ask {
	$|=1;
	my($q,$d) = @_;
	my($sin) = new_from_fd FileHandle(STDIN, "r");
	if(length($q." [".$d."]: ") > 80) {
		print $q, "\n[", $d, "]: ";
	}
	else {
		print $q, " [", $d, "]: ";
	}
	chomp(my($l) = $sin->getline);
	$l;
}

sub ver2tag {
	my($ver) = @_;
	my($maj,$min,$sub,$pre) = split_version($ver);
	"$STATE-$maj-$min$sub".($pre?"-pre$pre":'');
}

sub split_version {
	my($ver) = @_;
	my($maj,$min,$sub,$pre);
	$ver =~ m/(\d)\.(\d)(\w)/o;
	($maj,$min,$sub) = ($1, $2, $3);
	$ver =~ m/-pre(\d+)/o;
	($maj,$min,$sub,$1);
}

sub next_version {
	my($ver)=@_;
	my($maj,$min,$sub,$pre) = split_version($ver);
	$sub++;
	"$maj.$min$sub";
}

sub version_part {
	my($maj,$min,$sub,$pre) = split_version($_[0]);
#	"$maj.$min$sub".($pre?"-pre$pre":'');
	"$maj.$min$sub";
}

sub make_version_file {
	my($ver) = @_;
	if($nonono) {
		print "Would have made LC/version.pm with the version number $ver.\n";
		return;
	}
	print "Writing LC/version.pm, version $ver\n";
	if(-f "LC/version.pm") { unlink "LC/version.pm"; }
	my($fh) = new FileHandle("LC/version.pm", "w");
	if(!$fh) { die $!; }

	print $fh qq(
# version.pm
# Automatically generated by Build.PL.
#
package LC::version;
use Exporter;
\@ISA = qw(Exporter);
\@EXPORT = qw(\$TL_VERSION);
\$TL_VERSION = '$ver';
1;
);
	close $fh;
	chmod(0444, "LC/version.pm");
}

sub tilde_expand {
	my($inp) = @_;

	my(@inp) = split('/', $inp);

	foreach $pe (@inp) {
		if($pe eq '~') {
			my($name,$passwd,$uid,$gid,$quota,$comment,$gcos,$dir,$shell) =
			    getpwuid($>);
			if(!$dir) {
				print "No home directory for uid ", $>, ", ignoring ~.\n";
				next;
			}
			$pe = $dir;
		}
		elsif($pe =~ /~(\w+)/o) {
			my($name,$passwd,$uid,$gid,$quota,$comment,$gcos,$dir,$shell) =
			    getpwnam($1);
			if(!$dir) {
				print "No home directory for user ", $1, ", ignoring ~", $1,
				    ".\n";
				next;
			}
			$pe =~ s/~(\w+)/$dir/;
		}
	}
	join("/", @inp);
}
