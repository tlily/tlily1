# -*- Perl -*-
package LC::Extend;

use Exporter;
use Safe;
use LC::UI;
use LC::Server;
use LC::parse;
use LC::User;
use LC::Command;
use LC::State;
use LC::log;
use LC::config;

@ISA = qw(Exporter);

@EXPORT = qw(extension);

# initial version, 10/24/97, Josh Wilmes

# Provide a secure environment for user extensions to TigerLily.  We use
# a Safe to provide strict control over what the extensions have access to.

sub extension {
    my ($filename)=@_;
    my @share=();

    $safe=new Safe;

    log_notice("loading \'$filename\'");

    # Since security isnt a primary concern, I allow all perl operators to be
    # used.
    # note that due to changes in the safe module in 5.002 vs newer versions,
    # and my lack of an old version to test on, things might not quite work
    # on older perls.
    if ($Safe::VERSION >= 2) {
	$safe->deny_only("system");
	$safe->permit("system");
    } else {
	$safe->mask($safe->emptymask());
    }

    push @share,@LC::UI::EXPORT;
    push @share,@LC::Server::EXPORT;
    push @share,@LC::parse::EXPORT;
    push @share,@LC::User::EXPORT;
    push @share,@LC::Command::EXPORT;
    push @share,@LC::State::EXPORT;
    push @share,@LC::log::EXPORT;
    push @share,@LC::config::EXPORT;
    $TL_VERSION=$main::TL_VERSION;
    push @share,qw($TL_VERSION);
    
    $safe->share (@share);
        
    $safe->rdo($filename);
    ui_output("* error: $@") if $@;
}


