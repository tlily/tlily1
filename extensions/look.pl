#
# "look" tlily extension
#

sub spellcheck($$$) {
    my($key, $line, $pos) = @_;

    $a = substr($line, 0, $pos);
    $a =~ s/.*\s+//;

    $b = substr($line, $pos);
    $b =~ s/\s.*//;

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
