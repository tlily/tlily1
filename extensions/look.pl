# $Header: /data/cvs/tlily/extensions/look.pl,v 1.6 1998/06/05 03:22:49 mjr Exp $
#
# "look" tlily extension
#

sub spellcheck($$$) {
    my($key, $line, $pos) = @_;

    # First get the portion of the line from the beginning to the
    # character just before the cursor.
    $a = substr($line, 0, $pos);
    # Just keep the alphabetic characters at the end (if any).
    $a =~ s/.*?([A-Za-z]*)$/$1/;

    # The rest of the line, from the cursor to the end.
    $b = substr($line, $pos);
    # Just keep the alphabetic characters at the beginning (if any).
    $b =~ s/[^A-Za-z].*//;

    $word = $a . $b;
    return if ($word eq '');

    @res = `look $word`;
    chomp(@res);

    my $clen = 0;
    foreach (@res) { $clen = length $_ if (length $_ > $clen); }
    $clen += 2;

    my $cols = int($ui_cols / $clen);
    my $rows = int(@res / $cols);
    $rows++ if (@res % $cols);

    $rows = 5 if ($rows > 5);

    my $i;
    for ($i = 0; $i < $rows; $i++) {
	ui_output(sprintf("%-${clen}s" x $cols,
			  map{$res[$i+$rows*$_]} 0..$cols));
    }

    if (@res > $rows * $cols) {
	ui_output("(" . (@res - ($rows * $cols)) . " more entries follow)");
    }

    return;
}

ui_callback('C-g', \&spellcheck);
