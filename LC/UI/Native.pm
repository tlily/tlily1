# -*- Perl -*-
# $Header: /data/cvs/tlily/LC/UI/Native.pm,v 1.5 1998/10/28 21:19:14 neild Exp $
package LC::UI::Native;

=head1 NAME

LC::UI:Native - tlily's native user interface.

This implementation of the UI module is targeted at simple text screens.
It uses an abstraction layer to access the screen, as defined by the
CTerminal module.  (Curses based, currently the only functioning implementation
of the terminal layer.)

=cut

use POSIX qw(isprint);
use LC::Config;
use LC::UI::Basic;
use vars qw(@ISA @EXPORT);

@ISA=qw(LC::UI::Basic);


# What is a line?  A line is a text string, with attached formatting
# information.  A single line may span multiple rows on the screen; if
# so, it must be word-wrapped.  The internal representation of a line
# separates the text and formatting information.  The formatting information
# is contained in a list.  This list is a sequence of formatting commands;
# any command may be followed by a set of arguments.  Possible commands are:
#   FOwrapchar <wrapchar>
#   FOwrap
#   FOnewline
#   FOattr <attr>
#   FOpopattr
#   FOtext <length>

my $FOnull      = 0;
my $FOwrapchar  = 1;
my $FOwrap      = 2;
my $FOnewline   = 3;
my $FOattr      = 4;
my $FOpopattr   = 5;
my $FOtext      = 6;

# count of how many LC::UI::Native's are running.
my $native_ui_running = 0;

sub new {    
    my $class = shift;
    my %self;
    my $self=bless \%self,$class;

    $self->{input_line} = '';
    $self->{input_prompt} = '';
    $self->{input_height} = 1;
    $self->{input_fline} = 0;
    $self->{input_pos} = 0;
    @{$self->{input_history}} = ('');
    $self->{input_curhistory} = 0;
    $self->{input_killbuf} = "";
    $self->{input_pastemode} = 0;
    $self->{page_status} = 'normal';
    $self->{status_line} = "";
    $self->{status_intern} = "";
    $self->{status_update_time} = 0;
    @{$self->{accepted_lines}} = ();
    %{$self->{attr_list}} = ();
    @{$self->{attr_stack}} = ();
    %{$self->{filter_list}} = ();

    # wow! closures! ;)
    %{$self->{key_trans}} = ('kl'   => [ sub { $self->input_left(@_); }      ],
			     'C-b'  => [ sub { $self->input_left(@_); }      ],
			     'kr'   => [ sub { $self->input_right(@_); }     ],
			     'C-f'  => [ sub { $self->input_right(@_); }     ],
			     'ku'   => [ sub { $self->input_prevhistory(@_);}],
			     'C-p'  => [ sub { $self->input_prevhistory(@_);}],
			     'kd'   => [ sub { $self->input_nexthistory(@_);}],
			     'C-n'  => [ sub { $self->input_nexthistory(@_);}],
			     'C-a'  => [ sub { $self->input_home(@_); }      ],
			     'C-e'  => [ sub { $self->input_end(@_); }       ],
			     'C-k'  => [ sub { $self->input_killtoend(@_); } ],
			     'C-u'  => [ sub { $self->input_killtohome(@_); }],
			     'pgup' => [ sub { $self->input_pageup(@_); }    ],
			     'M-v'  => [ sub { $self->input_pageup(@_); }    ],
			     'pgdn' => [ sub { $self->input_pagedown(@_); }  ],
			     'C-v'  => [ sub { $self->input_pagedown(@_); }  ],
			     'M-['  => [ sub { $self->input_scrollup(@_); }  ],
			     'M-]'  => [ sub { $self->input_scrolldown(@_); }],
			     'M-<'  => [ sub { $self->input_scrollfirst(@_);}],
			     'M->'  => [ sub { $self->input_scrolllast(@_); }],
			     'C-t'  => [ sub { $self->input_twiddle(@_); }   ],
			     'nl'   => [ sub { $self->input_accept(@_); }    ],
			     'C-y'  => [ sub { $self->input_yank(@_); }      ],
			     'C-w'  => [ sub { $self->input_killword(@_); }  ],
			     'C-l'  => [ sub { $self->input_refresh(@_); }   ],
			     'M-p'  => [ sub { $self->input_pastemode(@_); } ],
			     'C-d'  => [ sub { $self->input_del(@_); }       ],
			     'C-h'  => [ sub { $self->input_bs(@_); }        ],
			     'bs'   => [ sub { $self->input_bs(@_); }        ],
			     'home' => [ sub { $self->input_homekey(@_); }   ],
			     'end'  => [ sub { $self->input_endkey(@_); }    ]
			     );

    # A list of lines in the text window.  These lines are stored unformatted.
    @{$self->{text_lines}} = (" ");

    # A list of formatting information for the text window.
    @{$self->{text_fmts}} = ( [] );

    # A list of line heights.  This is a cache; any line's height as stored
    # in here may be undef.  (We don't seem to be able to my this one; we need
    # to use it in a handler passed down to the terminal module.)    
    @{$self->{text_heights}} = ( 1 );

    # A list of filters associated with each line.
    @{$self->{text_filters}} = ( [] );

    # A list of unparsed lines.  Lines only appear in here if they contain 
    # filters.
    @{$self->{text_unparsed}} = ( " " );

    # The line and row in said line which are anchored to the bottom of the
    # text window.
    $self->{text_l} = 0;
    $self->{text_r} = 0;

    # The number of rows which have been scrolled up since the user last
    # examined the screen.
    $self->{scrolled_rows} = 0;

    return $self;
}


# Starts the curses UI.
sub ui_start() {
    my ($self)=@_;

    if ($native_ui_running) {
	die "Error:  Only one LC::UI::Native UI can be run at a time.\n";
    }

    $native_ui_running++;

    $config{'terminal'} ||= 'LC::CTerminal';
    eval "use $config{'terminal'};";
    if ($@) {
	print STDERR "Error: cannot initialize terminal \"$config{terminal}\".\n";
	print STDERR $@, "\n";
	exit;
    }
    $self->{term} = $config{'terminal'}->new();
    $self->{term}->term_init(sub {
	$self->{ui_cols} = $self->{term}->term_cols;
	@{$self->{text_heights}} = ();
	$self->{text_r} = 0;
	$self->scroll_info();
	$self->{status_update_time} = 0;
	$self->redraw;
    });
    $self->{ui_cols} = $self->{term}->term_cols;

    # Set colors from what the config files read
    if($config{mono}) {
	my($k,$v);
	while (($k,$v) = each %{$config{'mono_attrs'}}) {
	    $self->ui_attr($k, @{$v});
	}
    }
    else {
	my($k,$v);
	while (($k,$v) = each %{$config{'color_attrs'}}) {
	    $self->ui_attr($k, @{$v});
	}
    }
    $self->redraw;

    # This has to be here because it is after the ui is initialized.
    config_register_callback(Variable => 'mono', State => 'STORE',
			     Call => sub {
	my($tr, %ev) = @_;
	if($config{mono} == 0 && ${$ev{Value}} == 1) {
	    $self->ui_clearattr();
	    while (($k,$v) = each %{$config{'mono_attrs'}}) {
		$self->ui_attr($k, @{$v});
	    }
	    $self->redraw();
	    $self->redraw(); # Hack!
	} elsif($config{mono} == 1 && ${$ev{Value}} == 0) {
	    $self->ui_clearattr();
	    while (($k,$v) = each %{$config{'color_attrs'}}) {
		$self->ui_attr($k, @{$v});
	    }
	    $self->redraw();
	}
	return 0;
    });
    config_register_callback(Variable => '-ALL-',
                             List => 'color_attrs',
                             State => 'STORE',
                             Call => sub {
	my($tr, %ev) = @_;
	if($config{mono}==0) {
	    $self->ui_attr(${$ev{Key}}, @{${$ev{Value}}});
            $self->redraw();
	}
    });
    config_register_callback(Variable => '-ALL-',
                             List => 'mono_attrs',
                             State => 'STORE',
                             Call => sub {
	my($tr, %ev) = @_;
	if($config{mono}==1) {
	    $self->ui_attr(${$ev{Key}}, @{${$ev{Value}}});
	    $self->redraw();
	}
    });

}


# Terminates the UI.
sub ui_end() {
    my ($self)=@_;

    $self->{term}->term_end();

    $native_ui_running--;
}


# Define a new attribute.
sub ui_attr($@) {
    my($self, $name, @attrs) = @_;
    $self->{attr_list}->{$name} = \@attrs;
}

# Invalidate a filter.
sub ui_resetfilter($) {
    my($self, $name) = @_;
    my $i;
    for ($i = 0; $i <= @{$self->{text_lines}}; $i++) {
	next unless (grep { $_ eq $name } @{$self->{text_filters}->[$i]});
	
	my($line, $fmt, $filters);
	($line, $fmt, $filters) = $self->fmtline($self->{text_unparsed}->[$i]);
	unshift @$fmt, $self->{text_fmts}->[$i][0,1]
	    if ($self->{text_fmts}->[$i]->[0] == $FOwrapchar);

	$self->{text_lines}->[$i] = $line;
	$self->{text_fmts}->[$i] = $fmt;
	$self->{text_filters}->[$i] = $filters;
	$self->{text_heights}->[$i] = undef;
    }

    $self->win_redraw();
}

# Define a new filter.
sub ui_filter($$) {
    my($self, $name, $sub) = @_;
    $self->{filter_list}->{$name} = $sub;
    $self->ui_resetfilter($name);
}

# Clear all attributes.
sub ui_clearattr() {
    my ($self)=@_;

    %{$self->{attr_list}} = ();
}

# Selects an attribute for use.
sub attr_use($) {
    my($self, $name) = @_;

    my @curattrs = $self->{term}->term_getattr();
    push @{$self->{attr_stack}}, \@curattrs;

    return if (!defined $self->{attr_list}->{$name});

    my $attrs = $self->{attr_list}->{$name};
    $self->{term}->term_setattr(@$attrs);
}


# Pops attribute usage stack.
sub attr_pop() {
    my ($self)=@_;

    my $attrs = pop @{$self->{attr_stack}};
    $self->{term}->term_setattr(@$attrs);
}


# Rolls out the attribute stack.
sub attr_top() {
    my ($self)=@_;

    my $attrs;
    while (@{$self->{attr_stack}}) {
	$attrs = pop @{$self->{attr_stack}};
    }
    $self->{term}->term_setattr(@$attrs);
}


# Draws one line (or a subset of the rows in a line) at a given position.
sub win_draw_line($$$$@) {
    my($self, $ypos, $line, $fmt, $start, $count) = @_;

    my $p = 0;
    my $l = 0;
    my $x = 0;
    my $y = $ypos;
    my $wrapchar = '';

    $self->attr_use('text_window');
    $self->{term}->term_move($y, 0);
    $self->{term}->term_delete_to_end();

    my $i;
    for ($i = 0; $i < scalar(@$fmt); $i++) {
	if ($fmt->[$i] == $FOwrapchar) {
	    $wrapchar = $fmt->[++$i];
	} elsif (($fmt->[$i] == $FOwrap) || ($fmt->[$i] == $FOnewline)) {
	    if (!defined($start) || ($l >= $start)) {
		$self->{term}->term_addstr(' ' x ($self->{term}->term_cols - $x));
	    }

	    $l++;
	    last if ((defined $count) && ($l >= $start + $count));
	    next if (defined($start) && ($l < $start));

	    unless (defined($start) && ($l == $start)) {
		$self->{term}->term_move(++$y, 0);
		$self->{term}->term_delete_to_end();
	    }

	    if ($fmt->[$i] == $FOwrap) {
		$self->{term}->term_addstr($wrapchar);
		$x = length $wrapchar;
	    } else {
		$x = 0;
	    }
	} elsif ($fmt->[$i] == $FOtext) {
	    $i++;
	    if ((!defined($start)) || ($l >= $start)) {
		$self->{term}->term_addstr(substr($line, $p,
				   (($fmt->[$i] < ($self->{term}->term_cols-$x)) ?
				    $fmt->[$i] : $self->{term}->term_cols - $x)));
		$x += $fmt->[$i];
	    }
	    $p += $fmt->[$i];
	} elsif ($fmt->[$i] == $FOattr) {
	    $self->attr_use($fmt->[++$i]);
	} elsif ($fmt->[$i] == $FOpopattr) {
	    $self->attr_pop();
	}
    }

    $self->attr_top();
}

# fmtline is called with a line of <tag>formatted</tag> text.  It returns
# ($line, $fmt, $filters).
sub fmtline($) {
    my($self, $text) = @_;

    $text =~ s/\\\\//g;
    $text =~ s/\\\<//g;
    $text =~ tr/</</;
    $text =~ s/\\(.)/$1/g;
    $text =~ tr//\\/;

    my $line = '';
    my @fmt = ();

    my %filters = ();

    while (length $text) {
	if ($text =~ /^(([^\>]*)\>\>)/) {
	    # <<filter>>
	    $text = substr($text, length $1);
	    my $tag = $2;
	    my $m;
	    if ($text =~ /^((.*?)\/$tag\>\>)/) {
		$text = substr($text, length $1);
		$m = $2;
	    } else {
		$m = $text;
		$text = '';
	    }

	    $m = &{$self->{filter_list}->{$tag}}($m) 
		if ($self->{filter_list}->{$tag});
	    $text = $m . $text;

	    $filters{$tag}++;
	} elsif ($text =~ /^(\/([^\>]*)\>)/) {
	    # </tag>
	    $text = substr($text, length $1);
	    push @fmt, $FOpopattr;
	} elsif ($text =~ /^(([^\>]*)\>)/) {
	    # <tag>
	    $text = substr($text, length $1);
	    push @fmt, $FOattr, $2;
	} elsif ($text =~ /^(\r?\n)/) {
	    # newline
	    $text = substr($text, length $1);
	    push @fmt, $FOnewline;
	} elsif ($text =~ /^([^\r\n]+)/) {
	    # text
	    $text = substr($text, length $1);
	    $line .= $1;
	    push @fmt, $FOtext, length $1;
	}
    }

    return ($line, \@fmt, [keys %filters]);
}


# This function performs line wrapping.  It takes an line and format pair,
# and returns the number of rows spanned by the line.  The format information
# is modified to break the line across rows.
sub line_wrap($$) {
    my($self, $line, $fmt) = @_;

    # Tack a trailing element onto the format array.  This permits the loop
    # below to execute one more time, simplifying some of the logic.
    push @$fmt, $FOnull;

    # @fmt contains the NEW format information that we construct.  Perhaps
    # I should not have given it the same name as $fmt (the OLD format
    # information), but what is done is done.
    my @fmt = ();

    # $idx is an index into the string.  It marks the beginning of the text
    # that has not yet been packed into the new format string.
    my $idx = 0;

    # $x is the current column of the output cursor.
    my $x = 0;

    # $len is the length of the string that is currently being constructed.
    my $len = 0;

    # $rows is the number of rows to be occupied by the line.  This is always
    # at least one: a null line still occupies a row.
    my $rows = 1;

    # Keep an eye on the wrapchars (the prefix string to be output before
    # each wrapped line of text.)
    my $wrapchar = '';

    # Walk down the old format, processing each code in turn.
    while (@$fmt) {
	my $t = shift @$fmt;

	if ($t == $FOwrapchar) {
	    $wrapchar = shift @$fmt;
	    push @fmt, $t, $wrapchar;
	    next;
	} elsif ($t == $FOwrap) {
	    # We just ignore these -- they are the results of previous
	    # line_wrap operations.
	    next;
	} elsif ($t == $FOtext) {
	    $len += shift @$fmt;
	    next;
	}

	# If we have reached this point, we shall want to commit the text
	# (if any) we have currently pending.

	if ($len) {
	    while ($len + $x > $self->{term}->term_cols) {
		# The current chunk of text is too long!  We need to wrap it.

		# Locate the character at which we may break the line.
		my $tmp = rindex(substr($line, $idx, $self->{term}->term_cols - $x+1), ' ');

		if (($tmp == -1) || (($self->{term}->term_cols - $x - $tmp) > 10)) {
		    # There is no adequate breakpoint: we will just have to
		    # split a word.
		    $tmp = $self->{term}->term_cols - $x;
		} else {
		    $tmp++;
		}

		push @fmt, $FOtext, $tmp, $FOwrap;
		$x = length $wrapchar;
		$idx += $tmp;
		$len -= $tmp;
		$rows++;
	    }

	    # Whatever text remains will fit on the current row; commit it.
	    push @fmt, $FOtext, $len;
	    $idx += $len;
	    $x += $len;
	    $len = 0;
	}

	if ($t == $FOnewline) {
	    push @fmt, $FOnewline;
	    $x = 0;
	    $rows++;
	} elsif ($t == $FOattr) {
	    push @fmt, $FOattr, shift @$fmt;
	} elsif ($t == $FOpopattr) {
	    push @fmt, $FOpopattr;
	}
    }

    @$fmt = @fmt;
    return $rows;
}


# Returns the height of a line, in rows.  If necessary, line_wrap() is called
# on the line, and the result is stored in the @{$self->{text_heights}} cache.
sub line_height($$) {
    my($self, $idx) = @_;
    if (!defined $self->{text_heights}->[$idx]) {
	$self->{text_heights}->[$idx] = $self->line_wrap($self->{text_lines}->[$idx], $self->{text_fmts}->[$idx]);
    }
    return ($self->{text_heights}->[$idx]);
}


# Redraws the text window.
sub win_redraw() {
    my ($self) = @_;

    my $y = $self->win_height() - $self->{text_r};
    my $l = $self->{text_l};

    while (($y > 0) && ($l > 0)) {
	$self->win_draw_line($y, $self->{text_lines}->[$l],
			     $self->{text_fmts}->[$l], 0,
			     $self->win_height() - $y + 1);

	$l--;
	$y -= $self->line_height($l) if ($l > 0);
    }

    if (($l > 0) && ($self->line_height($l) > -$y)) {
	$self->win_draw_line(0, $self->{text_lines}->[$l],
			     $self->{text_fmts}->[$l], 
			     -$y, $self->win_height());
    } else {
	while (--$y > 0) {
	    $self->{term}->term_move($y, 0);
	    $self->{term}->term_delete_to_end();
	}
    }

    $self->input_position_cursor();
}


# Scrolls the text window.
sub win_scroll($$) {    
    my($self, $n) = @_;

    if ($n > 0) {
	my $i;
	for ($i = 0; $i < $n; $i++) {
	    $self->{text_r}++;
	    if ($self->{text_r} >= $self->line_height($self->{text_l})) {
		$self->{text_r} = 0;
		$self->{text_l}++;
		last if ($self->{text_l} > $#{$self->{text_lines}});
	    }

	    $self->{term}->term_move(0,0);
	    $self->{term}->term_delete_line();
	    $self->{term}->term_move($self->win_height(),0);
	    $self->{term}->term_insert_line();
	    
	    $self->win_draw_line($self->win_height(),
			  $self->{text_lines}->[$self->{text_l}],
				 $self->{text_fmts}->[$self->{text_l}],
				 $self->{text_r}, 1);	
	}
    } elsif ($n < 0) {
	my $i;

	my($top_r, $top_l) = ($self->{text_r}, $self->{text_l});
	for ($i = 0; $i < $self->win_height(); $i++) {
	    $top_r--;
	    if ($top_r < 0) {
		$top_l--;
		$top_r = ($top_l < 0) ? 0 : $self->line_height($top_l) - 1;
	    }
	}

	for ($i = 0; $i > $n; $i--) {
	    $self->{text_r}--;
	    if ($self->{text_r} < 0) {
		$self->{text_l}--;
		last if ($self->{text_l} < 0);
		$self->{text_r} = $self->line_height($self->{text_l}) - 1;
	    }

	    $top_r--;
	    if ($top_r < 0) {
		$top_l--;
		$top_r = ($top_l < 0) ? 0 : $self->line_height($top_l) - 1;
	    }

	    $self->{term}->term_move($self->win_height(),0);
	    $self->{term}->term_delete_line();
	    $self->{term}->term_move(0,0);
	    $self->{term}->term_insert_line();

	    if ($top_l >= 0) {
		$self->win_draw_line(0, $self->{text_lines}->[$top_l],
				     $self->{text_fmts}->[$top_l],
				     $top_r, 1);
	    } else {
		$self->{term}->term_delete_to_end();
	    }
	}
    }

    if ($self->{text_l} < 0) {
	$self->{text_l} = 0;
	$self->{text_r} = 0;
    } elsif ($self->{text_l} > $#{$self->{text_lines}}) {
	$self->{text_l} = $#{$self->{text_lines}};
	$self->{text_r} = $self->line_height($self->{text_l}) - 1;
    }

    $self->input_position_cursor();
}


# Adds a line of text to the text window.
sub ui_output {
    my $self=shift;
    my %h=@_;   

    my($line, $fmt, $filters);
    ($line, $fmt, $filters) = $self->fmtline($h{Text});
    unshift @$fmt, $FOwrapchar, $h{WrapChar} if ($h{WrapChar});

    push @{$self->{text_lines}}, $line;
    push @{$self->{text_fmts}}, $fmt;
    push @{$self->{text_filters}}, $filters;
    push @{$self->{text_unparsed}}, (@{$filters} ? $h{Text} : undef);

    my $h = $self->line_height($#{$self->{text_lines}});

    if ($self->{scrolled_rows} + $h >= $self->win_height()) {
	$h = $self->win_height() - $self->{scrolled_rows} - 1;
    }
    if (($h > 0) && ($self->{text_l} == $#{$self->{text_lines}} - 1) &&
	($self->{text_r} == $self->line_height($self->{text_l}) - 1)) {
      $self->{scrolled_rows} += $h  if ($config{pager});
	$self->win_scroll($h);
    }

    $self->scroll_info();
    $self->{term}->term_refresh();
}


# Returns the size (in lines) of the text window.
sub win_height($) {
    my ($self)=@_;

    return $self->{term}->term_lines - 2 - $self->{input_height};
}


# Redraws the status line.
sub sline_redraw($) {
    my ($self)=@_;

    my $s;
    if ($self->{page_status} eq 'normal') {
	$s = $self->{status_line};
    } else {
	my $t = time;
	return if ($t == $self->{status_update_time});
	$self->{status_update_time} = $t;
	$s = $self->{status_intern};
    }
    my $sline = "<status_line>" . $s . (' ' x $self->{term}->term_cols) . "</status_line>";
    my $sfmt;
    ($sline, $sfmt) = $self->fmtline($sline);
    $self->win_draw_line($self->{term}->term_lines-1-$self->{input_height}, $sline, $sfmt);
    $self->input_position_cursor();
}


# Sets the status line.
sub ui_status($$) {
    my ($self, $s) = @_;

    $self->{status_line} = $s;
    $self->sline_redraw();
    $self->{term}->term_refresh();
}


# Positions the input cursor.
sub input_position_cursor($) {
    my ($self)=@_;

    my $xpos = length($self->{input_prompt});
    $xpos += $self->{input_pos} unless ($self->{password});
    $self->{term}->term_move($self->{term}->term_lines - $self->{input_height} + int(($xpos / $self->{ui_cols})) - $self->{input_fline},
	      $xpos % $self->{ui_cols});
}


# Redraws the input line.
sub input_redraw($) {
    my ($self)=@_;
    
    $self->attr_use('input_line');

    my $l = $self->{input_prompt};
    $l .= $self->{input_line} unless ($self->{password});

    my $height = int((length($l) / $self->{ui_cols})) + 1 - $self->{input_fline};
    $height = 1 if ($height < 1);

    $self->{term}->term_move($self->{term}->term_lines - 1, 0);
    $self->{term}->term_delete_to_end();

    my $i;
    for ($i = 0; $i < length($l) / $self->{ui_cols}; $i += 1) {
	next if ($i < $self->{input_fline});
	$self->{term}->term_move($self->{term}->term_lines - $height + $i, 0);
	$self->{term}->term_delete_to_end();
	$self->{term}->term_addstr(substr($l,$i*$self->{ui_cols},$self->{ui_cols}));
    }

    if ($self->{input_height} != $height) {
	$self->{input_height} = $height;
	$self->win_redraw();
	$self->sline_redraw();
    }

    $self->input_position_cursor();
    $self->attr_top();
}


# Restores sanity to the input cursor.
sub input_normalize_cursor($) {
    my ($self)=@_;

    if ($self->{input_pos} > length $self->{input_line}) {
	$self->{input_pos} = length $self->{input_line};
    } elsif ($self->{input_pos} < 0) {
	$self->{input_pos} = 0;
    }
}


# Inserts a character into the input line.
sub input_add($$$$) {
    my($self, $key, $line, $pos) = @_;

    $line = substr($line, 0, $pos) . $key . substr($line, $pos);

    return ($line, $pos + 1, 2) if ($self->{password});

    my $l = $self->{input_prompt} . $line;
    if (length($l) % $self->{term}->term_cols == 0) {
	return ($line, $pos + 1, 2);
    }

    my $ii = $self->{input_height} - $self->{input_fline} - 1;
    my $i = $ii;
    while ($i * $self->{term}->term_cols > $pos + length($self->{input_prompt})) {
	$self->{term}->term_move($self->{term}->term_lines - $self->{input_height} + $i, 0);
	$self->{term}->term_insert_char();
	$self->{term}->term_addstr(substr($l, $i * $self->{term}->term_cols, 1));
	$i--;
    }
    $self->input_position_cursor();
    $self->{term}->term_insert_char();
    $self->{term}->term_addstr($key);
    return ($line, $pos + 1, 0);
}


# Moves the input cursor left.
sub input_left($$$$) {
    my($self, $key, $line, $pos) = @_;

    return ($line, $pos - 1, 1);
}


# Moves the input cursor right.
sub input_right($$$$) {
    my($self, $key, $line, $pos) = @_;

    return ($line, $pos + 1, 1);
}


# Moves the input cursor to the beginning of the line.
sub input_home($$$$) {
    my($self, $key, $line, $pos) = @_;

    return ($line, 0, 1);
}


# Moves the input cursor to the end of the line.
sub input_end($$$$) {
    my($self, $key, $line, $pos) = @_;

    return ($line, length $line, 1);
}


# Deletes the character before the input cursor.
sub input_bs($$$$) {
    my($self, $key, $line, $pos) = @_;

    return if ($pos == 0);
    $line = substr($line, 0, $pos - 1) . substr($line, $pos);

    return ($line, $pos + 1, 2) if ($self->{password});

    my $l = $self->{input_prompt} . $line;

    if (length($l) % $self->{term}->term_cols == 0) {
	return ($line, $pos - 1, 2);
    }

    my $ii = $self->{input_height} - $self->{input_fline} - 1;
    my $i = $ii;
    while ($i * $self->{term}->term_cols > $pos) {
	$self->{term}->term_move($self->{term}->term_lines - $self->{input_height} + $i, 0);
	$self->{term}->term_delete_char();
	$i--;
	$self->{term}->term_move($self->{term}->term_lines - $self->{input_height} + $i, $self->{term}->term_cols - 1);
	$self->{term}->term_addstr(substr($l, ($i * $self->{term}->term_cols) + $self->{term}->term_cols - 1, 1));
    }
    $self->input_position_cursor();
    $self->{term}->term_delete_char();
    return ($line, $pos - 1, 2);
}


# Deletes the character after the input cursor.
sub input_del($$$$) {
    my ($self, $key, $line, $pos) = @_;

    return if ($pos >= length($line));
    return $self->input_bs('', $line, $pos + 1);
}


# Yanks the kill bufffer back.
sub input_yank($$$$) {
    my ($self, $key, $line, $pos) = @_;

    $line = substr($line, 0, $pos) . $self->{input_killbuf} . substr($line, $pos);
    return ($line, $pos + length($self->{input_killbuf}), 2);
}


# Deletes the word preceding the input cursor.
sub input_killword($$$$) {
    my ($self, $key, $line, $pos) = @_;

    my $l = $line;
    substr($line, 0, $pos) =~ s/(\S+\s*)$//;
    $self->{input_killbuf} = $1;
    return ($line, $pos - length($1), 2);
}


# Deletes all characters to the end of the line.
sub input_killtoend($$$$) {
    my($self, $key, $line, $pos) = @_;

    $self->{input_killbuf} = substr($line, $pos);
    return (substr($line, 0, $pos), $pos, 2);
}


# Deletes all characters to the beginning of the line.
sub input_killtohome($$$$) {
    my($self, $key, $line, $pos) = @_;

    $self->{input_killbuf} = substr($line, 0, $pos);
    return (substr($line, $pos), 0, 2);
}


# Rotates the position of the previous two characters.
sub input_twiddle($$$$) {
    my($self, $key, $line, $pos) = @_;

    return if ($pos == 0);
    $pos++ if ($pos < length($line));
    my $tmp = substr($line, $pos-2, 1);
    substr($line, $pos-2, 1) = substr($line, $pos-1, 1);
    substr($line, $pos-1, 1) = $tmp;
    return ($line, $pos, 2);
}


# Moves back one entry in the history.
sub input_prevhistory($$$$) {
    my($self, $key, $line, $pos) = @_;

    return if ($self->{input_curhistory} <= 0);
    $self->{input_history}->[$self->{input_curhistory}] = $line;
    $self->{input_curhistory}--;
    $line = $self->{input_history}->[$self->{input_curhistory}];
    return ($line, length $line, 2);
}


# Moves forward one entry in the history.
sub input_nexthistory($$$$) {
    my($self, $key, $line, $pos) = @_;

    return if ($self->{input_curhistory} >= $#{$self->{input_history}});
    $self->{input_history}->[$self->{input_curhistory}] = $line;
    $self->{input_curhistory}++;
    $line = $self->{input_history}->[$self->{input_curhistory}];
    return ($line, length $line, 2);
}


# Handles entry of a new line.
sub input_accept($$$$) {
    my($self, $key, $line, $pos) = @_;

    return $self->input_add(' ', $line, $pos) if ($self->{input_pastemode});

    if (($line eq '') && ($self->{input_prompt} eq '') &&
        (($self->{text_l} != $#{$self->{text_lines}}) ||
	 ($self->{text_r} != $self->line_height($self->{text_l}) - 1))) {
	$self->input_pagedown();
	return ($line, $pos, 0);
    }

    $self->{input_prompt} = '';
    $self->{input_curhistory} = $#{$self->{input_history}};

    if (($line ne '') && (!$self->{password})) {
	$self->{input_history}->[$#{$self->{input_history}}] = $line;
	push @{$self->{input_history}}, '';
	$self->{input_curhistory} = $#{$self->{input_history}};
    }

    push @{$self->{accepted_lines}}, $line;
    $self->{input_fline} = 0;
    return ('', 0, 2);
}


# Redraw the UI screen.
sub input_refresh($$$$) {
    my($self, $key, $line, $pos) = @_;
    $self->redraw();
    return($line, $pos, 0);
}


# Toggles paste mode.
sub input_pastemode($$$$) {
    my($self, $key, $line, $pos) = @_;

    my $paste_prompt = "Paste: ";
    if ($self->{input_pastemode}) {
	$self->ui_prompt("") if ($self->{input_prompt} eq $paste_prompt);
	$self->{input_pastemode} = 0;
    } else {
	$self->ui_prompt($paste_prompt) unless ($self->{input_prompt});
	$self->{input_pastemode} = 1;
    }
    return($line, $pos, 0);
}


# Page up.
sub input_pageup($$$$) {
    my($self, $key, $line, $pos) = @_;

    $self->win_scroll(-$self->win_height());
    $self->scroll_info();
    $self->{term}->term_refresh();
    return($line, $pos, 0);
}


# Page down.
sub input_pagedown($$$$) {
    my($self, $key, $line, $pos) = @_;

    $self->win_scroll($self->win_height());
    $self->scroll_info();
    $self->{term}->term_refresh();
    return($line, $pos, 0);
}


# Scroll up.
sub input_scrollup($$$$) {
    my($self, $key, $line, $pos) = @_;

    my $scroll = $config{ui_customscroll} || $self->win_height()/2;
    $self->win_scroll(-$scroll);
    $self->scroll_info();
    $self->{term}->term_refresh();
    return($line, $pos, 0);
}


# Scroll down.
sub input_scrolldown($$$$) {
    my($self, $key, $line, $pos) = @_;

    my $scroll = $config{ui_customscroll} || $self->win_height()/2;
    $self->win_scroll($scroll);
    $self->scroll_info();
    $self->{term}->term_refresh();
    return($line, $pos, 0);
}


# To first line
sub input_scrollfirst($$$$) {
    my($self, $key, $line, $pos) = @_;

    $self->{text_l} = 0;
    $self->{text_r} = 0;

    my $rows = 1;
    while (($rows < $self->{term}->term_lines) && ($self->{text_l} <= $#{$self->{text_lines}})) {
	$rows++;
	$self->{text_r}++;
	if ($self->{text_r} >= $self->line_height($self->{text_l})) {
	    $self->{text_l}++;
	    $self->{text_r} = 0;
	}
    }
    if ($self->{text_l} > $#{$self->{text_lines}}) {
	$self->{text_l} = $#{$self->{text_lines}};
	$self->{text_r} = $self->line_height($self->{text_l}) - 1;
    }

    $self->win_redraw();
    $self->{term}->term_refresh();
    return($line, $pos, 0);
}


# To last line
sub input_scrolllast($$$$) {
    my($self,$key, $line, $pos) = @_;

    $self->{text_l} = $#{$self->{text_lines}};
    $self->{text_r} = $self->line_height($self->{text_l}) - 1;
    $self->win_redraw();
    $self->{term}->term_refresh();
    return($line, $pos, 0);
}

sub input_homekey($$$$) {
    my($self,$key,$line,$pos) = @_;

    if($pos == 0) {
	$self->input_scrollfirst($key,$line,$pos);
    } else {
	$self->input_home($key,$line,$pos);
    }
}

sub input_endkey($$$$) {
    my($self,$key,$line,$pos) = @_;

    if($pos == length $line) {
	$self->input_scrolllast($key,$line,$pos);
    } else {
	$self->input_end($key,$line,$pos);
    }
}


# Redraws the UI screen.
sub redraw($) {
    my ($self)=@_;

    $self->{term}->term_clear();
    $self->win_redraw;
    $self->sline_redraw();
    $self->input_redraw;
    $self->{term}->term_refresh();
}


# Returns scrollback information.
sub scroll_info($) {
    my ($self)=@_;

    if (($self->{text_l} != $#{$self->{text_lines}}) || ($self->{text_r} != $self->line_height($self->{text_l}) - 1)) {
	my $lines = $self->line_height($self->{text_l}) - $self->{text_r} - 1;
	my $i;
	for ($i = $self->{text_l} + 1; $i <= $#{$self->{text_lines}}; $i++) {
	    $lines += $self->line_height($i);
	}
	$self->{page_status} = 'more';
	$self->{status_intern} = "-- MORE ($lines) --";
	$self->{status_intern} = (' ' x int(($self->{term}->term_cols - length($self->{status_intern})) / 2)) . $self->{status_intern};
	$self->sline_redraw();
	$self->{term}->term_refresh();
    } else {
	$self->{page_status} = 'normal';
	$self->sline_redraw();
	$self->{term}->term_refresh();
    }
}


# Registers an input callback function.
sub ui_callback($$$) {
    my($self, $key, $cb) = @_;
    push @{$self->{key_trans}->{$key}}, $cb;
}


# Deregisters an input callback function.
sub ui_remove_callback($$$) {
    my($self, $key, $cb) = @_;
    @{$self->{key_trans}->{$key}} = grep { $_ ne $cb } @{$self->{key_trans}->{$key}};
}


# Accepts input from the terminal.
sub ui_process($) {
    my ($self)=@_;

    my $c;

    while (1) {
	$c = $self->{term}->term_get_char();
	last if ((!defined($c)) || ($c eq '-1'));

	$self->{scrolled_rows} = 0;
	$self->{status_update_time} = 0;

	$self->attr_use('input_line');

	my @res;
	foreach (@{$self->{key_trans}->{$c}}) {
	    @res = &$_($c, $self->{input_line}, $self->{input_pos});
	    last if (@res);
	}
	if ((scalar(@res) == 0) && isprint($c) && length($c) == 1) {
	    @res = $self->input_add($c, $self->{input_line}, $self->{input_pos});
	}

	if (@res) {
	    my $update = 0;
	    ($self->{input_line}, $self->{input_pos}, $update) = @res;
	    $self->input_normalize_cursor();
	    if ($update == 1) {
		$self->input_position_cursor();
	    } elsif ($update == 2) {
		$self->input_redraw();
		$self->{term}->term_refresh();
	    }
	}

	$self->attr_top();
    }	

    $self->scroll_info();
    return shift @{$self->{accepted_lines}};
}


# Rings the bell.
sub ui_bell($) {
    my ($self)=@_;
    $self->{term}->term_bell();
}


# Sets password (noecho) mode.
sub ui_password($$) {
    my ($self,$pass)=@_;
    $self->{password} = $pass;
}


# Sets the prompt.
sub ui_prompt($$) {
    my ($self,$prompt)=@_;
    $self->{input_prompt} = $prompt;
    $self->input_redraw();
    $self->{term}->term_refresh();
}


sub ui_select($$$$$) {
    my($self, $r, $w, $e, $t) = @_;
    return $self->{term}->term_select($r, $w, $e, $t);
}

1;

