# -*- Perl -*-
package LC::gag;

use POSIX;
use Exporter;

@ISA = qw(Exporter);

@EXPORT = qw(&muffle %gagged);


%gagged = ();

sub muffle ($) {
    my($line) = @_;
    my $new = $line;

    $new =~ s/\b\w\b/m/g;
    $new =~ s/\b\w\w\b/mm/g;
    $new =~ s/\b\w\w\w\b/mrm/g;
    $new =~ s/\b(\w+)\w\w\w\b/'m'.('r'x length($1)).'fl'/ge;

    my $i;
    for ($i = 0; $i < length($line); $i++) {
	substr($new, $i, 1) = toupper(substr($new, $i, 1))
	    if (isupper(substr($line, $i, 1)));
    }

    return $new;
}

1;
