# -*- Perl -*-
package LC::Expand;

use Exporter;

use LC::UI;

@ISA = qw(Exporter);

@EXPORT = qw(&exp_set &exp_expand &exp_init);

my %expansions = ('sendgroup' => '',
		  'sender'    => '',
		  'recips'    => '');

sub exp_set ($$) {
    my($a,$b) = @_;
    $expansions{$a} = $b;
}


sub exp_expand ($$$) {
    my($key, $line, $pos) = @_;

    return LC::UI::input_add($key, $line, $pos) if ($pos != 0);

    my $exp;
    if ($key eq '=') {
	$exp = $expansions{'sendgroup'};
	$key = ';';
    } elsif ($key eq ':') {
	$exp = $expansions{'sender'};
    } elsif ($key eq ';') {
	$exp = $expansions{'recips'};
    } else {
	return LC::UI::input_add($key, $line, $pos);
    }

    return ($exp . $key . $line, length($exp) + 1, 2);
}

sub exp_init () {
    ui_callback(':' => \&exp_expand);
    ui_callback(';' => \&exp_expand);
    ui_callback('=' => \&exp_expand);
}
