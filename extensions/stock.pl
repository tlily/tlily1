my @timer_ids;
my $info = "STOCK";
my $ticker = "^DJI";
my $freq = 15;

register_user_command_handler('stock', \&stock_cmd);
register_help_short('stock', "Show stock ticker updates in your status bar");
register_help_long('stock','%stock stop                   stop ticker,
%stock <TICKER SYMBOL list>   display oneshot update for stocks. (NYI)
%stock -t <TICKER SYMBOL>     start tracking stock (default is $ticker)
%stock -f <frequency>         frequency in seconds to update statusbar
                              (defaults to $freq)
%stock -l                     show current settings.
');


#
# return stock quote information for the given stocks..
# (although we only ever use -one-, this is more extensible)
#

sub disp_stock {

  @stock = @_;
  $cmd = "wget -O- -q 'http://quote.yahoo.com/q?s=" . join("+",@stock) . "&d=v1'
";
  open (N,"$cmd|") or return "Quote for $stock failed";

  @retval = () ;
  $cnt = 0;
  while (<N>) {
    if (! m:^(</tr>)?<tr align=right>:) {next};
    <N>; #discard symbol line
    chomp( $last_time = <N> ) ;
    chomp( $last_value = <N> ) ;
    chomp( $change_frac = <N> ) ;
    chomp( $change_perc = <N> ) ;
    chomp( $volume = <N> ) ;
    $last_time =~ s/(<[^>]*>)//g;
    $last_value =~ s/(<[^>]*>)//g;
    $change_frac =~ s/(<[^>]*>)//g;
    $change_perc =~ s/(<[^>]*>)//g;
    $volume =~ s/(<[^>]*>)//g;

    ui_output("($stock[$cnt]: last trade: $last_time, $last_value. Change: $change_frac ($change_perc). Volume: $volume)");
    $cnt++;
  }
  close(N);
}

sub track_stock {

  my @stock = @_;

  $cmd = "wget -O- -q 'http://quote.yahoo.com/q?s=" . join("+",@stock) . "&d=v1'";
  open (N,"$cmd|") or return "Quote for $stock failed";
  @retval = () ;
  $cnt = 0;
  while (<N>) {
    if (! m:^(</tr>)?<tr align=right>:) {next};
    <N>; <N>; #toss 2 lines
    chomp( $last_value = <N> ) ;
    chomp( $change_frac = <N> ) ;
    $last_value =~ s/(<[^>]*>)//g;
    $change_frac =~ s/(<[^>]*>)//g;
    push @retval, "$stock[$cnt]: $last_value ($change_frac)";
    $cnt++;
  }
  close(N);
  return join("",@retval);
}

#
# stop any statusline updates we're doing..
#

sub unload {
  foreach (@timer_ids) {
    deregister_handler($_);
  }
  @timer_ids = ();
}


#
# update the stock price every $freq seconds...
#

sub setup_handler {

  $timer_id = register_timedhandler(Interval => $freq, Repeat => 1,
                                    Call => sub {
                                                 $info = track_stock($ticker);
                                                 redraw_statusline();
			                        });
  push @timer_ids, $timer_id;
}


#
# setup our statusline handler and begin our default ticker
#

register_statusline(Var => \$info, Position => "PACKRIGHT");
redraw_statusline();
setup_handler();


#
# Handle any new requests for information
#
sub stock_cmd {

  (my $cmd) = @_;

  if ($cmd eq "stop") {
    $ticker = "" ;
    unload();
  } elsif ($cmd =~ /^-t\s*(.*)/) {
    unload();
    $ticker = $1;
    $info = "Waiting for $ticker";
    redraw_statusline();
    setup_handler();
  } elsif ($cmd =~ /^-f\s*(.*)/) {
    unload();
    $freq = $1;
    setup_handler();
  } elsif ($cmd eq "-l") {
    ui_output("(Tracking: '$ticker' at a frequency of $freq seconds.)");
  } else {
    disp_stock(split(/\s+/,$cmd));
  }
}

1;
