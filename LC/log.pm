package LC::log;

use Exporter;
use IO::File;
use LC::time_stamp;

@ISA = qw(Exporter);

@EXPORT = qw(&log_notice &log_err &log_info &log_debug $timestamp);

tie $timestamp, 'LC::time_stamp';

sub log_notice {
    main::ui_output("*** @_\n");
}

sub log_err {
    main::ui_end();
    print "*ERROR* $timestamp @_\n";
    exit(1);
}


sub log_info {
    main::ui_output("*INFO* $timestamp @_\n");
}

sub log_debug {
    my $s=IO::File->new(">>/tmp/foo.log");
    print $s "*DEBUG* $timestamp @_\n";
}
