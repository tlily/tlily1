#!/usr/bin/perl

use Config;
use Carp;
use File::Copy;
use File::Path;
use FileHandle;
use DirHandle;
use Cwd;

### Configure Me

$VERSION='0.2b';
$CVSTAG='release-0-2b';

#$PREFIX='/usr/local';
##$PREFIX="$ENV{'HOME'}/inst";
#$BINDIR=$PREFIX."/bin";
#$LIBDIR=$PREFIX."/lib/tlily";
#$LIBMODDIR=$LIBDIR; # the LC dir will be made below this
#$LIBEXTDIR=$LIBDIR."/extensions";

# for local testing/hacking/use: uncomment these and  perl Build.PL
$PREFIX=Cwd::cwd;
$BINDIR=$PREFIX;
$LIBDIR=$PREFIX;
$LIBMODDIR=$LIBDIR; # the LC dir will be made below this
$LIBEXTDIR=$LIBDIR."/extensions";

### You shouldn't have to change anything below this line.

$PERL = $Config{'startperl'} ||
        $Config{'perlpath'}? "#!".$Config{'perlpath'} : '' ||
        "#/usr/bin/perl";

while(@ARGV) {
	# this first part doesn't work yet.
	if($ARGV[0] =~ /[A-Z_]*=.*$/o) {
		$ARGV[0] =~ s/=(.*)$/=\'$1\'/;
		$ARGV[0] = '$'.$ARGV[0];
		print $ARGV[0], "\n";
		eval $ARGV[0];
		if($@) { carp $@; exit(1); }
		shift;
	}
	elsif($ARGV[0] eq "-n") {
		$nonono = 1; shift;
	}
	elsif($ARGV[0] eq "-d") {
		$debug = 1; shift;
	}
	elsif($ARGV[0] eq "-h") {
		&Usage;
	}
	else {
		$target=shift;
	}
}

print "-d: $debug\n" if $debug;
print "-n: $nonono\n" if $debug;

$moddir="LC";
$extdir="extensions";
$modext='\.pm';
$extext='\.e';
@modfiles = &get_files($moddir, $modext);
@extfiles = &get_files($extdir, $extext);
print join("\n", @modfiles), "\n" if $debug;
print join("\n", @extfiles), "\n" if $debug;

if(!$target) {
	&make_tlily;
}
elsif($target eq 'install') {
	&make_tlily;
	
	&install('DIR' => $BINDIR, 'MODE' => 0755);
	&install('FILE' => 'tlily',
	         'DEST' => $BINDIR.'/tlily',
	         'MODE' => 0755);

	&install('DIR' => "$LIBMODDIR/$moddir", 'MODE' => 0755);

	my($file);
	foreach $file (@modfiles) {
		&install('FILE' => "$moddir/$file",
		         'DEST' => "$LIBMODDIR/$moddir/$file",
		         'MODE' => 0644);
	}

	&install('DIR' => $LIBEXTDIR, 'MODE' => 0755);

	foreach $file (@extfiles) {
		&install('FILE' => "$extdir/$file",
		         'DEST' => "$LIBEXTDIR/$file",
		         'MODE' => 0644);
	}
}
elsif($target eq 'release') {
	print "This part does not work yet.\n";
	my($cmd) = 'cvs rtag $CVSTAG tigerlily';
	print "(not executed) ", $cmd, "\n";
	$cmd = $Config{'tar'} || "tar";
	$cmd .= " cf tlily-$VERSION.tar tlily.PL Build.PL";
	foreach(@modfiles) {
		$cmd .= " $moddir/$_";
	}
	foreach(@extfiles) {
		$cmd .= " $extdir/$_";
	}
	print "(not executed) ", $cmd, "\n";
	$cmd = $Config{'gzip'} || "gzip";
	$cmd .= " -9 tlily-$VERSION.tar";
	print "(not executed) ", $cmd, "\n";
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
			$rc = mkpath($dir, 0, $mode); 
			if(!$rc) { croak $dir,": ",$!; }
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
	my($ifh) = new FileHandle("tlily.PL", "r");
	die $! if not $ifh;

	my($ofh) = new FileHandle("tlily", "w");
	if(!$ofh) {
		my($msg) = $!; close($ifh); die $msg;
	}

	while(<$ifh>) {
		s|\@\@PERL\@\@|$PERL|;
		s|\@\@VERSION\@\@|$VERSION|;
		s|\@\@LIBMODDIR\@\@|$LIBMODDIR|;
		s|\@\@LIBEXTDIR\@\@|$LIBEXTDIR|;
		print $ofh $_;
	}
	close($ifh);
	close($ofh);
	chmod(0755, "tlily");
}

sub Usage {
	print qq(
Usage: perl Build.PL [-n][-h][install|release]
	-n: Show what would have been done without actually doing it.
	-h: Show this help
	install: do variable substitutions on tlily.PL and install TigerLily
	release: tag the release via CVS and make a .tar.gz for release
);
	exit(1);
}
