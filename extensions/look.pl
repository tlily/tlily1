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

    foreach (@res) {
	ui_output $_;
    }

    return;
}

ui_callback('C-g', \&spellcheck);
