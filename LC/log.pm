package LC::log;

use Exporter;
use IO::File;
@ISA = qw(Exporter);

@EXPORT = qw(&log_notice &log_err &log_info &log_debug);



sub log_notice {
    main::ui_output("*** @_\n");
}

sub log_err {
    main::ui_end();
    print "*ERROR* @_\n";
    exit(1);
}


sub log_info {
    main::ui_output("*INFO* @_\n");
}

sub log_debug {
    my $s=IO::File->new(">>/tmp/foo.log");
    print $s "*DEBUG* @_\n";
}
