# -*- Perl -*-

# This is Josh's first attempt at a much more modular architecture for UI
# modules.  Module, modular, mod, module modulation modulator.
#
# This same idea should also be applicable to other parts of tlily, so I think
# it's worth a shot.

# Here is the basic theory behind this implementation:
# UI.pm will now has a concept of "registering" more than one UI.
#   The first UI that is registered is the "default" UI.  All undirected
#      events or function calls go to this UI.  
#   If addtional UI's are registered, then events can be directed to those
#      particular ones.
#
# Event direction will be performed by adding a Target to the events,
# and passing that into ui_output.
#
# All the other functions that don't take hash-style arguments can now
# optionally take an extra argument (the first one) indicating the target.
#
# If it is not supplied, the default target is used.
#
# For example, with a graphical UI, multiple windows could be instantiated
# as multiple UI instances.
#

# NOTE:  Need to handle select loops more intelligently!  For now we just use
# the select loop of the default UI.  In addition, $ui_cols is bound to the
# default UI.

package LC::UI;

use LC::Config;

use Exporter;
@ISA = qw(Exporter);

use vars qw(@ISA @EXPORT $ui_cols $ui_loaded);
use strict;

$ui_loaded = 1;

@EXPORT = qw(&ui_start
	     &ui_end
	     &ui_attr
	     &ui_filter
	     &ui_resetfilter
	     &ui_clearattr
	     &ui_output
	     &ui_status
	     &ui_process
	     &ui_callback
	     &ui_remove_callback
	     &ui_bell
	     &ui_password
	     &ui_prompt
	     &ui_select
	     $ui_cols
	     &ui_escape
	    );

my (%ui_map,$save_default_ui);

sub ui_start { 
    my ($target,$type)=@_;
    if (! $target) {
	if ($ui_map{default} && ! $save_default_ui) {
	    die "A default UI has already been registered!\n";
	} else {
	    $target='default';
	}
    }
    
    $config{'UI'} ||= 'Native';
    $type ||= $config{'UI'};

    my $UI; 

    if ($target eq "default" && defined($save_default_ui)) {
	$UI=$save_default_ui;
	undef $save_default_ui;
    }	    

    if (! $UI) {
	eval "use LC::UI::$type; \$UI=new LC::UI::$type()";
	die "Unable to load UI module: $@\n" if $@;
	die "Error instantiating LC::UI::$type\n" unless ($UI);
    }

    $UI->ui_start($target); 
    # need to use a tied scalar here, for the time being.  $ui_cols should
    # die..
    tie $ui_cols, 'ui_col_tie';

    $ui_map{$target}=$UI;
}

sub ui_end {
    my ($target)=@_;
    
    $target ||= "default";

    $ui_map{$target}->ui_end();
    if ($target eq "default") {
	# because we may want to restart the default ui, we do _not_ destroy
	# it if it is shut down.   This should be replaced with a ui_savestate
	# and ui_restorestate function in each ui module later, but for now
	# this hack should suffice.

	$save_default_ui=$ui_map{$target} 
    } else {
	delete $ui_map{$target};
    }
}

sub ui_attr {     
    my ($target,@args)=("default",@_);
    if (@_ == 3) { ($target,@args)=@_; } 

    $target="default" unless $ui_map{$target};
    $ui_map{$target}->ui_attr(@args);
}

sub ui_filter {
    my ($target,@args)=("default",@_);
    if (@_ == 3) { ($target,@args)=@_; } 

    $target="default" unless $ui_map{$target};
    $ui_map{$target}->ui_filter(@args);
}

sub ui_resetfilter {
    my ($target,@args)=("default",@_);
    if (@_ == 2) { ($target,@args)=@_; } 

    $target="default" unless $ui_map{$target};
    $ui_map{$target}->ui_resetfilter(@args);
}

sub ui_status { 
    my ($target,@args)=("default",@_);
    if (@_ == 2) { ($target,@args)=@_; } 

    $target="default" unless $ui_map{$target};
    $ui_map{$target}->ui_status(@args);
}

sub ui_process {
    my ($target)=@_;

    $target ||= "default";

    $target="default" unless $ui_map{$target};
    $ui_map{$target}->ui_process();
}

sub ui_callback {
    my ($target,@args)=("default",@_);
    if (@_ == 3) { ($target,@args)=@_; } 

    $target="default" unless $ui_map{$target};
    $ui_map{$target}->ui_callback(@args);
}

sub ui_remove_callback {
    my ($target,@args)=("default",@_);
    if (@_ == 3) { ($target,@args)=@_; } 

    $target="default" unless $ui_map{$target};
    $ui_map{$target}->ui_remove_callback(@args);
}

sub ui_bell {
    my ($target)=@_;

    $target ||= "default";

    $target="default" unless $ui_map{$target};
    $ui_map{$target}->ui_bell();
}

sub ui_password {
    my ($target,@args)=("default",@_);
    if (@_ == 2) { ($target,@args)=@_; } 
        
    $target="default" unless $ui_map{$target};
    $ui_map{$target}->ui_password(@args);
}

sub ui_prompt {
    my ($target,@args)=("default",@_);
    if (@_ == 2) { ($target,@args)=@_; } 

    $target="default" unless $ui_map{$target};
    $ui_map{$target}->ui_prompt(@args);
}

sub ui_select($$$$) {
    # FIX ME
    $ui_map{default}->ui_select(@_);
}

sub ui_output {
    my %h;
    if (@_ == 1) {
	%h = (Text => $_[0]);
    } else {
	%h = @_;
    }

    my $target = $h{Target} || 'default';

    $target="default" unless $ui_map{$target};
    $ui_map{$target}->ui_output(%h); 
}

sub ui_escape($) {
    my ($line)=@_;
    $line =~ s/\</\\\</g; $line =~ s/\>/\\\>/g;
#    $line =~ s/\\\\([<>])/\\$1/g;  #what the heck!

    return $line;
}


# this little class is necessary as glue for the time being.  $ui_cols needs
# to go away and be replaced with something more intelligent.
package ui_col_tie;
require Tie::Scalar;

use vars qw(@ISA);
@ISA = ("Tie::StdScalar");

sub FETCH { $ui_map{default}->{ui_cols}; }

1;

=head1 NAME

LC::UI - User input/output layer.

=head1 SYNOPSIS

    ui_start();
    ui_output('foo');
    ui_end();

=head1 DESCRIPTION

The UI module provides an interface to the user.  It is intended to be
modular -- it should be possible to use it to talk to just about any
kind of user interface you might want, (such as an X-based one).

Individual UI modules can be added to the system by creating a new module
derived from LC::UI::Basic.  This module will detect them and make them
available with the UI config option.

=head2 Functions

=over 10

=item ui_start()

This function must be called prior to any other UI functions.  Once it has
been called, the terminal should be considered inaccessible (i.e., do not
use any print statements afterwards).

=item ui_end()

Must be called prior to exiting the program.  The terminal is again
accessible after this function is called.

=item ui_attr()

Defines an attribute tag.  Takes the name of the tag and a list of attributes
to associate with this name.  (See the CTerminal documentation for a list
of attributes.)

    ui_attr('b', 'bold');
 or ui_attr($Target, 'b', 'bold');

=item ui_output()

Sends a line of output to the user.  There are two forms of this command
which may be used: one takes the line to send as its only argument, the
other takes a hash of parameters.  The line text is given in the 'Text'
parameter.

The passed line may contain HTML-style attribute tags, such as <b>.  All
tags used must be first defined with the ui_attr() function.  Text sent
with this function is drawn with the 'text_window' tag by default.

Backslashes may be used to quote '<' characters that do not begin
attribute tags.  Backslashes must themselves be quoted.

The text may contain embedded newlines.

The 'WrapChar' parameter may be given to specify a prefix to use for
wordwrapped lines of output.

    ui_output(' -> From <user>damien</user>');
    ui_output(Text => ' -> From <user>damien</user>',
	      WrapChar => ' -> ');

=item ui_status()

Sets the status line.  This text may contain attribute tags.  The status
line is drawn with the 'status_line' tag by default.

    ui_status('<suser>damien</suser>');

=item ui_process()

Handles user input.  Returns a single line of user input, if one is available,
or undef otherwise.

=item ui_callback()

Registers a user key callback handler.  Takes two arguments: a key, and
a code reference to call when that key is pressed.  The callback will
be called with three arguments: the key pressed, the current input line,
and the current position in the input line (as an index).  A callback
may return a list of three elements: the new input line, the new position,
and a flag.  If this flag is 0, no further action is taken.  If it is 1,
the input cursor is repositioned.  If it is 2, the input line is redrawn
and the cursor is repositioned.  A callback may return null, in which case
the input line remains unchanged.

Callbacks are called in the reverse order of definition.  A successful
return from a callback prevents all subsequent callbacks from running.

    # Turn |s into pipes.
    sub pipe_conv($$$) {
	my($key, $line, $pos) = @_;
	$line = substr($line, 0, $pos) . 'pipe' .
	    substr($line, $pos);
	return ($line, $pos + 4, 2);
    }
    ui_callback('|', \&pipe_conv);

=item ui_remove_callback()

Removes a currently registered user key callback handler.  Takes the
same arguments as ui_callback().

=item ui_bell()

Rings the terminal bell.

=item ui_password()

Turns password mode on and off.  When password mode is active, input does
not display on the input line, and lines are not saved in the input history.
Takes a boolean argument to specify if password mode should be turned on
or off.

    ui_password(1);  # Enable password mode.

=item ui_prompt()

Sets the input prompt.  The prompt is displayed as a prefix on the input
line.  The prompt is cleared after each line accepted from the user.

    ui_prompt("login: ");

=back

=head2 Variables

=over 10

=item $ui_cols

The width of the display in characters.  (The height is intentionally not
provided.)

=back

=cut

