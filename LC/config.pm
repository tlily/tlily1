package LC::config;

use Exporter;
@ISA = qw(Exporter);

@EXPORT = qw(%config);

$config{server}='albert.einstein.to';
#$config{server}='lily.acm.rpi.edu';
$config{port}=7777;
$config{login}='wilmesj';  $config{pass}='borfument';

1;
