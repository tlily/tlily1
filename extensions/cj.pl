# -*- Perl -*-
# $Header: /data/cvs/tlily/extensions/cj.pl,v 1.1 2000/09/08 02:58:40 coke Exp $

use strict;

#
# cj.pl
# 
# CJ began life as a special purpose Magic 8Ball resident on a private
#   lily, server side. He has since switched to client side (obviously. =-)
#   and begun dispensing quotes, both witty and stock. 
# Author:
my $MAINTAINER = "Coke";
#   Will Coleda vaguely takes responsibility for the current incarnation.
#   (But not for the quote files, or any of the items in the memos on the
#    server)
# "BUGS":
#   Stroke@RPI 4/20 - track CPQ, track cpq : stocks are case sensitive on
#                     track, but not at yahoo.com. should be fixed.

my @TODO = (
"Allow different responsiveness levels per discussion.
     3 types: ignore (CJ is there just to spit out updates)
              quiet  (commands must -begin- a send)
              chatty (CJ agressively responds to everything)",
"fix cnnJ headline news to parse other cnn sites (like cnnsi, cnnfn, etc)",
);

### INITIALIZATION

### where do the files we need live?
my $basedir = "/home/wjc/research/CJ";

### who watches the watchbot?
my $adminDisc = "cj-admin";

### who was I again? 
my $cj_regexp = "(cj|jo|cyberjo|sausage)";

### a regexp of other bots I should ignore to avoid the Strider Dilemma.
$bots_regexp ="(mj|Mechajosh|cj|navi 1.02|botulism|coketest|lilybot)";

### for the stock tracking: what, how, how often.
my @stock_tracked;
my $stock_timer_id;
my $stock_freq = 600 ; # seconds
my $stock_disc = "-quote" ; 
my $stock_max_lookup = 10;

### for the headline tracking:
my $news_timer_id;
my %news_headlines=();
my %news_status=();
my $news_counter = 0;
my @news_date_formats=();
my $news_freq = 300; # seconds
my $news_default = "-cj-news";

my %cnn_sites = (
  "Main"     => "http://www.cnn.com/",
  "World"    => "http://www.cnn.com/WORLD/",
  "U.S."     => "http://www.cnn.com/US/",
  "Politics" => "http://www.cnn.com/ALLPOLITICS/",
  "Space"    => "http://www.cnn.com/TECH/space/",
  "Nature"   => "http://www.cnn.com/NATURE/",
);

my %news_discussions = (
  "Main"     => $news_default,
  #"Nature"   => "-nature",
  #"Politics" => "-politics",
  #"Space"    => "-space",
  #"Sports"   => "-sports",
  #"World"    => "-world",
  #"US"       => "-usnews",
  #"Tech"     => "-tech",
  #"Finance"  => "-finance",
);

### Create a user Agent for web processing.
require LWP::UserAgent;
my $ua = new LWP::UserAgent;

### Create an Eliza instance
use Chatbot::Eliza;
my $eliza = new Chatbot::Eliza {name=>"CJ",prompts_on=>0};

### SUBROUTINE DEFINITIONS

### unload is called when we do %extension unload. Do any cleanup here.
sub stock_unload {
  deregister_handler($stock_timer_id);
  undef $stock_timer_id;
}

sub news_unload {
  deregister_handler($news_timer_id);
  undef $news_timer_id;
}                 

sub unload {
  stock_unload;
  news_unload;
}

### Wrap cmd_process in a useful fashion!
###  example:
###  do_command ("/info $adminDisc", sub { foreach (@_) { syslog($_); } } );

sub do_command {

  my $command = $_[0];
  my $subroutine = $_[1];

  # closure?

  my @data;
  $sub = sub {
    my($event) = @_;
    $event->{ToUser} = 0;
    if ($event->{Type} eq 'endcmd') {
      $subroutine->(@data);
      return;
    }
    return if $event->{Raw} =~ /^\%begin/ ;
    push @data, $event->{Raw};
    return;
  };
  cmd_process($command,$sub);
}

### If the caller is an admin, do what they want.
sub asAdmin {

  # who is trying?
  (my $user = $_[0]) =~ s/ /_/;

  # what was it we needed to do?
  my $sub = $_[1];

  $cmd = "/where $user";
  do_command($cmd, sub {
    $_[0] =~ m:is a member of (.*):;
    @discs = split ", ", $1;
    if (grep(/^$adminDisc$/, @discs)) {
      $sub->();
    } else {
      server("$user:I will NOT.");
    }
    } );
}

### Clean up HMTL for Presentation.
#
# This is already pretty unweidly.
#
sub cleanHTML {

  $a = join(" ",@_);

  $a =~ s/\n/ /;
  $a =~ s/<[^>]*>/ /g;
  $a =~ s/&lt;/</gi;
  $a =~ s/&gt;/>/gi;
  $a =~ s/&amp;/&/gi;
  $a =~ s/&#46;/./g;
  $a =~ s/&#039;/'/g;
  $a =~ s/&quot;/"/ig;
  $a =~ s/&nbsp;/ /ig;
  $a =~ s/&uuml;/u"/ig;
  $a =~ s/\s+/ /g;
  $a =~ s/^\s+//;

  return $a;
}

### pick an element of a list at random.
sub pick_message { return $_[int(rand(@_))]; }

### wrapping function for sends to the server. Takes a list.
sub server { server_send("@_\r\n"); }

### log stuff. 
sub syslog { server($adminDisc . ":" . join(" ",@_) ); }

### read in all the sayings and quotes....
sub read_files {
  undef @quotes; undef @cj_sayings; undef @unified_sayings;
  undef @stupid_sayings; undef @overhear_sayings;
  undef @nicknames; undef %definitions; undef %source;
  undef @stock_tracked, @buzzA, @buzzB, @buzzC;


  do_command("/memo $adminDisc buzzwordA", sub {
    foreach (@_) {
      s/^..//;
      push @buzzA, $_;
    }
  } );
  do_command("/memo $adminDisc buzzwordB", sub {
    foreach (@_) {
      s/^..//;
      push @buzzB, $_;
    }
  } );
  do_command("/memo $adminDisc buzzwordC", sub {
    foreach (@_) {
      s/^..//;
      push @buzzC, $_;
    }
  } );

  do_command("/memo $adminDisc stocks", sub {
    foreach (@_) {
      s/^..//;
      setup_stock_timer($_);
    }
  } );

  do_command("/memo $adminDisc sayings", sub {
    foreach (@_) {
      s/^..//;
      push @cj_sayings, $_;
    }
  } );

  do_command("/memo $adminDisc nicknames", sub {
    foreach (@_) {
      s/^..//;
      push @nicknames, $_;
    }
  } );

  do_command("/memo $adminDisc sorry", sub {
    foreach (@_) {
      s/^..//;
      push @sorry_sayings, $_;
    }
  } );

  do_command("/memo $adminDisc stupid", sub {
    foreach (@_) {
      s/^..//;
      push @stupid_sayings, $_;
    }
  } );

  do_command("/memo $adminDisc -unified", sub {
    foreach (@_) {
      s/^..//;
      push @unified_sayings, $_;
    }
  } );


  do_command("/memo $adminDisc overhear", sub {
    foreach (@_) {
      s/^..//;
      push @overhear_sayings, $_;
    }
  } );

  my $errors;

  open(F,"$basedir/quotes") or  $errors="had difficulty rereading quotes";
  while (<F>) { 
    chomp; 
    s// -- /;
    s/\\[nt]/ /g;
    s/  / /g;
    push @quotes, $_; 
  }
  close(F);

  open(F,"$basedir/definitions") or  $errors="had difficulty rereading quotes";
  while (<F>) {
    next if /^#/;
    chomp;
    my ($word,$src,$meaning)=split(//,$_);
    $definitions{$word}=$meaning;
    $source{$word}=$src;
    chomp;
  }
  close(F);
  
  if ($errors) {
    syslog($errors);
  } else {
    syslog("has initiated rereading of files.");
  }
}


### Address a message
sub address {
 (my $msg, my $from)= @_;

 if (!int(rand(10))) {
   $from = pick_message(@nicknames);
 }
 sprintf($msg,$from);
}

### Get polling information on the y2k presidential race.

sub get_polling_2k {

  my $wrap = 76;
  
  $url = "http://www.pollingreport.com/wh2gen.htm";
  my $response = $ua->request(HTTP::Request->new(GET => $url));
  return "It would appear that my connection to Polling Report is down." unless $response->is_success;

  # Parse this hideous output.
  # We can't seem to rely on having a particular table # here, so we'll
  # loop until we find what we want...

  my $gallup="";
  foreach my $tmp (split (/<table[^>]*>/i, $response->content)) {
    if ($tmp =~ /Zogby/ && $tmp =~ /Browne/) {
	($gallup = $tmp) =~ s/\n/ /g;
        last;
    }
  }

  if ($gallup eq "") {
    return "I can't seem to find your poll information. :(";
  }

  my @rows=(split (/<tr[^>]*>/i, $gallup));

  my @results;
  push @results, "According to $url: ";

  # DEBUG CODE
  #  my $cnt=0;
  #  foreach (@rows) {
  #    $result.="{$cnt: ";
  #    my @cells=(split (/<td[^>]*>/i, $_));
  #    my $cnt2=0;
  #    foreach (@cells) {
  #     $result.="{$cnt2: ".cleanHTML($_)."}";
  #     $cnt2++;
  #    } 
  #    $result.="}";
  #    $cnt++;
  #  }

  my @content;
  my $cnt=0;
  my $skip = 0;
  foreach (@rows) {
    if (/%/) {
	$skip=1; #skip from this line out.
    } elsif (/Zogby/) {
        $skip=0; #stop skipping...
        #DEBUG push @results, cleanHTML("Skipped line: $_");
	next;    #..but skip this line, regardless.
    }
    if (! $skip) {
      my @cells=(split (/<td[^>]*>/i, $_));
      $content[$cnt]=\@cells;
      $cnt++;
    } else {
      #DEBUG push @results, cleanHTML("Skipped line: $_") ;
	}
  }

  $dateROW = 2;
  $candROW = 1;

  # DEBUG output
  #my $cnt=0;
  #foreach my $row  (@content) {
    #push @results, "row $cnt:" . cleanHTML(join(" ", @{$row}));
    #$cnt++;
  #}

  (my $lv = cleanHTML($content[$dateROW][11])) =~ s/LV//;
  push @results, "For the date range: " . cleanHTML($content[$dateROW][2]) . "; polling " . $lv . "likely voters, ";

  foreach my $cnt (3..10) {
    $how = cleanHTML($content[$dateROW][$cnt]);
    $how =~ s/\s*$//;
    $how =~ s/^-$/0/;
    $content[$dateROW][$cnt] = $how;
  }


  sub byPerc {
    $content[$dateROW][$a] <=> $content[$dateROW][$b];
  }

  foreach my $cnt (reverse sort byPerc (3..10)) {
    $who = cleanHTML($content[$candROW][$cnt]);
    $who =~ s/- //g;
    $who =~ s:/ :/:g;
    $who =~ s/\s*$//;
    $how = $content[$dateROW][$cnt];
    push @results, "$who has $how%";
  }

  my $retval = "";
  foreach my $tmp (@results) {
    $pad = " " x ($wrap - ((length $tmp) % $wrap)) ;
    $retval .= $tmp . $pad;
  }

  return $retval;
}


### get headline news.
sub get_cnn_news {

  my ($day,$month,$year) = (localtime)[3..5];
  $year += 1900;
  $month = sprintf("%0.2i",++$month);
  $day = sprintf("%0.2i",$day);

  $news_date_formats[0] = "/" . $year . "/.*/" . $month . "/" . $day . "/";
  $news_date_formats[1] = "/" . $year % 100 . $month . "/" . $day . "/";

  foreach my $section (keys %cnn_sites) {
    #syslog ("is searching $section");
    my $response = $ua->request(HTTP::Request->new(GET => $cnn_sites{$section}))
;
    next if not $response->is_success;

    foreach my $link ($response->content =~ m:<a\s+.*?>[^<]*?</a>:gi) {
      
      $link =~ m:href="(.*?)":i ;
      my $href = $1;

      # Skip bogus headlines.
      my $headline = cleanHTML($link);

      next if $headline =~ m:^\s*$:g ;
      next if $headline =~ m:FULL STORY:g ;

      # All articles start with a relative URL attached to the root
      # of CNN.com (grrr. except for all the sites that don't live on
      # CNN.com. =-) and have a date of some kind embedded in them.
      # Avoid graphics.
      next if ! defined $href ;
      next if $href !~ m:^/:  ;
      next if $href =~ m:/toons/: ;

      #
      # Just show articles from today!
      #

      next if ! grep { $href =~ $_ } @news_date_formats;
      #syslog ("found an article after the date test");

      # canonicalize
      $href = "http://www.cnn.com" . $href;
      $href =~ s:index.html$::;  #remove "index.html"...
      $href =~ s:([^/])$:$1/:;   #add trailing / if it's not there.

      # We've already seen this one.
      next if (defined $news_headlines{$href});

      $news_headlines{$href}= $headline;
      $news_status{$href}{$section} = 0;
      #syslog("thinks this is an article");
    }
  }
}

### return stock quote information for the given stocks..
sub lookup_stock {

  my @stock = $_[0];

  my $url = "http://quote.yahoo.com/l?s=" . join("+",$stock) ;
  my $response = $ua->request(HTTP::Request->new(GET => $url));
  return "Lookup for @stock failed." unless $response->is_success;

  my @chunks = split ("<td>", $response->content);
  shift @chunks; # first chunk is spew.

  return "Sorry, no matches." if (!scalar(@chunks));

  @chunks = map {cleanHTML($_)} @chunks;

  #last chunk has spew at the end.
  $chunks[-1] =~ s/(.*)Select a Symbol.*/$1/; 

  my %retval = @chunks; 

  my $retval = "Possible matches include:  " ;
  my $cnt = 0;

  foreach (keys %retval) {
    if ($cnt++ > $stock_max_lookup) {
      chop $retval; chop $retval;
      $retval .= ". You matched more than $stock_max_lookup companies. Try limiting your search  ";
      last;
    }
    chop($retval{$_});
    $retval .= $_ . "(" . $retval{$_} . "); " ;
  }
 
  chop $retval; chop $retval; 
  $retval .= ".";
  return $retval;
}

sub get_stock {

  my @stock = @_;
  my @retval;
  my $cnt=0;
  my $wrap = 76;

  my $url = "http://finance.yahoo.com/q?s=" . join("+",@stock) . "&d=v1";
  my $response = $ua->request(HTTP::Request->new(GET => $url));
  return "Quote for @stock failed." unless $response->is_success;

  my @chunks = ($response->content =~ /^<td nowrap align=left>.*/mg);

  foreach (@chunks) {
    my ($time,$value,$frac,$perc,$volume) = (split(/<\/td>/,$_,))[1..5];

    if (/No such ticker symbol/) {
      push @retval, "$stock[$cnt]: Oops. No such ticker symbol. Try stock lookup.";
    } else {
      push @retval, "$stock[$cnt]: Last $time, $value: Change $frac ($perc): Vol $volume";
    }
    $cnt++;
  }

  my $retval = "";
  foreach my $tmp (@retval) {
    $tmp = cleanHTML($tmp);
    ## Tale requested some formatting cleanup:
    $tmp =~ s:(\d) / (\d):$1/$2:g;
    $tmp =~ s:\( :(:g;
    $tmp =~ s: \):):g;
    $tmp =~ s: ,:,:g;

    $pad = " " x ($wrap - ((length $tmp) % $wrap)) ;
    $retval .= $tmp . $pad;
  }
  
  $retval =~ s/\s*$//; 
  return $retval;
}

### return definition for a particular term from FOLDOC
sub get_foldoc {
 
  my $term = $_[0];

  my $url ="http://www.nightflight.com/cgi-bin/foldoc?query=" . $term; 
  my $response = $ua->request(HTTP::Request->new(GET => $url));
  return "It would appear that my connection to FOLDOC is down." unless $response->is_success;

  my $retval = cleanHTML((split("</FORM>",$response->content))[0]);

  if ($retval =~ /No match for/) {
    return "";
  }

  my @chunks = split("<HR>",$response->content);

  if (scalar(@chunks) == 3)  {
    return "According to FOLDOC: " . cleanHTML((split("</FORM>",$chunks[0]))[1]);
  } else {
    # multiple definitions... 
    return "";
  } } 
### return definition for a particular term from Mirriam Webster
sub get_webster {

  $term = $_[0];
  $url = "http://www.m-w.com/cgi-bin/dictionary?" . $term;
  my $response = $ua->request(HTTP::Request->new(GET => $url));
  return "It would appear that my connection to Webster is down." unless $response->is_success;

  # Was there anything?
  
  if ($response->content =~ /The word you've entered isn't in the dictionary/) {
    return "";
  }

  # Was there more than one match?
  @see_also=(); @other_forms=();
  if ($response->content =~/(\d+) words found/) {
    # all the words will appear in a dropdown, get the options.

    @options = grep {/^<option.*>(.*)$/} split(/\n/, $response->content);

    foreach $option (@options) {
      $option =~ s/<option.*>//;
      ($tmp = $option) =~ s/\[.*\]//g;
      if ($tmp eq $term) {
        # we get the first term for free already...
        $blah = quotemeta "[1,";
        if ($option !~ /$blah/) {
          push @other_forms, $option;
        }
      } else {
        push @see_also, $option;
      }
    }
  }

  # process the main form.
  ($retval = cleanHTML($response->content)) =~ s/^.*Main Entry: (.*)Get the Word.*/$1/;

  # Is there another form of the same name?
  if (scalar(@other_forms) >= 1) {
    #Need to figure out the magic incation to get the secondary data...
    #http://www.m-w.com/cgi-bin/dictionary?hdwd=murder&jump=a&list=a=700349
    #<input type=hidden name=list value="murder[1,noun]=700416;murder[2,verb]=700439;bloody murder=109479;self-murder=972362">

    $response->content =~ /<input type=hidden name=list value="(.*)">/;
    $list = $1;
 
    foreach $other_term (@other_forms) { 
      my $sub_url = "http://www.m-w.com/cgi-bin/dictionary?hdwd=" . $term . "&jump=" . $other_term . "&list=" . $list; 
      my $sub_response = $ua->request(HTTP::Request->new(GET => $sub_url));
      if ($sub_response->is_success) {
        ($sub_content= cleanHTML($sub_response->content)) =~ s/^.*Main Entry: (.*)Get the Word.*/$1/;
        $retval .= "; " . $sub_content;
      }
    }
  }
 # tack on any other items that turned up on the main list, for kicks.
  if (scalar(@see_also)) {
    $retval .= "| SEE ALSO: " . join(", ", @see_also);
  }
  return "According to Webster: " . $retval; 
}

### synonymize a word
sub get_syn {


  $term = $_[0];
  $url = "http://www.m-w.com/cgi-bin/dictionary?book=Thesaurus&" . $term;
  my $response = $ua->request(HTTP::Request->new(GET => $url));
  return "It would appear that my connection to Webster is down." unless $response->is_success;

  #my @retval = split(/<\/table>/i,$response->content);

  #shift @retval;
  #shift @retval;
 
  if ($response->content =~ /No entries found that match your query/) {
    syslog("cannot syn $term");
    return "";
  }

  #$retval=join(" ",@retval);
  ($retval = cleanHTML($response->content)) =~ s/^.*Entry Word: (.*)Get the Word.*$/$1/;

  syslog("is syn-ing $term");
  return "According to Webster: " . $retval; 
}



### define a word...
sub get_definition {

  my @terms=split(' ',$_[0]);
  my $dict = shift(@terms);
  my $term;

  ($term = join (" ",@terms)) =~ s/\s+/+/g;

  if ($dict eq "-webster") {
    $definition = get_webster($term);

    if ($definition ne "") { 
      syslog("is defining -webster $term");
    } else {
      syslog("cannot define -webster $term");
    }
    return $definition
  } elsif ($dict eq "-foldoc") {
    $definition = get_foldoc($term);

    if ($definition ne "") { 
      syslog("is defining -foldoc");
    } else {
      syslog("cannot define -foldoc $term");
    }
    return $definition
  } elsif ($dict =~ m:^-:) {
    syslog("cannot define @_");
    return "$dict? I don't know how to read that book yet.";
  } else {
    unshift @terms, $dict;
    ($term = join (" ",@terms)) =~ s/\s+/+/g;
  }

  my $definition;

  $definition = get_foldoc($term);

  if ($definition ne "") { 
    syslog("is defining $term");
    return $definition
  }

  $definition = get_webster($term);

  if ($definition ne "") { 
    syslog("is defining $term");
    return $definition
  }

  if ($definition eq "") {
    #
    # look it up in our local dictionary.
    #
    if (defined($definitions{$term})) {
      $definition = "According to " . $source{$term} . ", " . $term . ": " . $definitions{$term};
      syslog("is defining $term");
      return $definition;
    }
  }

  syslog("cannot define $term");
  return $definition
}

### report on tracked stocks. Called from the event handler
sub track {

  if (! defined(@stock_tracked) or $#stock_tracked == -1)  {
    # we're not tracking anything. kill the handler
    stock_unload;
    return 0;
  } 

  @stock_info = split(/ \|\| /,get_stock(@stock_tracked));
  foreach my $cnt (0..$#stock_tracked) {
    if (!defined $old_stock{$stock_tracked[$cnt]}) { $old_stock{$stock_tracked[$cnt]}="";}
    if ($stock_info[$cnt] ne $old_stock{$stock_tracked[$cnt]}) {
      server($stock_disc . ":" . $stock_info[$cnt]);
    } ;
    $old_stock{$stock_tracked[$cnt]} = $stock_info[$cnt];
  }
}

### setup a timer to deal with stock quotes.
sub setup_stock_timer {

  # always use the same timed_handler, if not there, init.

  if (! defined($stock_timer_id)) {
    $stock_timer_id = register_timedhandler(Interval => $stock_freq, 
                                                  Repeat => 1,
                                                  Call => \&track
                                     );
  }
  foreach my $stock (@_) {
    push @stock_tracked, $stock;
  }
}

### Either display a news article or grab new news
sub show_news {
  if (!($news_counter % 4)) {
    get_cnn_news; 

    my %count = ();
    foreach my $url (keys %news_status) {
      foreach my $section (keys %{$news_status{$url}}) {
        $count{$section}++;
      }
    }
    my $tmp = "has ". (keys %news_status) . " cnn headlines.";
    foreach my $section (keys %count) {
      $tmp .= " (" . $count{$section} . " in " . $section . ")";
    }
    syslog($tmp);
  }
  my @urls = ();
  foreach my $url (keys %news_status) {
    my $show = 0;
    foreach my $section (keys %{$news_status{$url}}) {
      $show ||= (! $news_status{$url}{$section});
    }
    if ($show) { push @urls,$url; }
  }

  #my @urls = grep { ! $news_status{$_} } (keys %news_status);

  my $num = scalar(@urls);
  if ($num) {
    $s = $num==1 ? "" : "s";
    #syslog("has " . scalar(@urls) . " article" . $s . " left to publish");
    my $url = pick_message(@urls);
    my $target = $news_default . "," ;
    foreach my $section (keys %{$news_status{$url}}) {
     if ($news_status{$url}{$section} == 0) {
       $news_status{$url}{$section} = 1;
       if (defined $news_discussions{$section}) {
         $target .= $news_discussions{$section} . "," ;
       }
     }
   }
  chop $target;
  my $message = $url . " : " . $news_headlines{$url} ;
  if ($target eq $news_default) {
   $message .= " (" . join(",",(keys %{$news_status{$url}})) . ")" ;
    } else {
      #syslog("target is $target");
    }
    $num=scalar(@urls)-1;
    $message .= " [" . $num . "]";
    server($target . ":" . $message);
  }
  $news_counter++;
}

### Handle incoming events.
sub cj_event {

  my($event) = $_[0];

  #
  # For Maker's sake, don't get caught in a loop..
  # 

  if ($event->{From} =~ m:^$bots_regexp$:i) {
    return 1;
  }

  undef @send_to ; undef $sendlist;

  @to_list = @{$event->{To}} ;
  if ($event->{Form} eq "private" ) { push @to_list, $event->{From} };
  foreach (@to_list) {
    if (! (m:^$cj_regexp$:i or m:^$bots_regexp$:i or m:^$adminDisc$:i) ) {
      push @send_to, $_ ;
    }
  } if (!defined (@send_to)) {return 1};
  ( $sendlist = (join ",", @send_to) ) =~ s/ /_/g;

  undef $message; 
  
  if ($event->{Body} =~ /^\s*quot(?:es?|h)\b\s+(.*)/i) {
    syslog("is quoting '$1'");
    $foo = quotemeta $1;
    @tmp = grep(/$foo/i,@quotes);
    if (scalar(@tmp) > 0) {
      $message = pick_message(@tmp);
    } else {
      $message = pick_message(@quotes);
    }
    undef @tmp;
    server("$sendlist:$message");
    return 1;
  } elsif ($event->{Body} =~ /^\s*define\b\s+(.*)/i) {
    $message = get_definition($1); 
    if ($message eq "") {
      $message = "I could find no definition to '$1'";
    }
    server("$sendlist:$message");
    return 1;
  } elsif ($event->{Body} =~ /^\s*syn\b\s+(.*)/i) {
    $message = get_syn($1); 
    if ($message eq "") {
      $message = "I could find no synonyms for '$1'";
    }
    server("$sendlist:$message");
    return 1;
  } elsif ($event->{Body} =~ /^\s*buzz/i) {
    $message = "Random Buzzword: " .  pick_message(@buzzA) . " " . pick_message(@buzzB) . " " .  pick_message(@buzzC);
    server("$sendlist:$message");
    return 1;
  }
  if ($event->{Form} eq "public" ) {
 
    # 8ball function. respond to directed questions.

    if ($event->{Body} =~ /\b${cj_regexp}\b.*\?\s*$/i) {
      if ($#to_list == 0 and ($to_list[0] eq "unified")) {
        # make it more likely to get the unified_sayings...
        $message = pick_message(@unified_sayings, @unified_sayings, @cj_sayings);
      } else { # it's not just unified
        $message = pick_message(@cj_sayings);
      }
      $message = address($message,$event->{From});
      syslog("is 8-balling");
    } elsif ($event->{Body} =~ /\b$cj_regexp\b/i) {
      # listen for my name, complain occasionally.
      if ($event->{Body} =~ /\bI'?m\b.*\bsorry\b/i) {
        $message=address(pick_message(@sorry_sayings), $event->{From});
      } else {
          if (!int(rand(3))) {
            $message = address(pick_message(@overhear_sayings),$event->{From});
          }
      }
    }
  } elsif ($event->{Form} eq "private") {
    if ($event->{Body} =~ m:^cmd\s+(.*):) {
      if ($1 eq "reread") {
        asAdmin($event->{From}, sub { read_files(); } );
      } elsif ($1 eq "forget") {
        ### mark all news as "read"
	asAdmin($event->{From}, sub {
	  map {$news_status{$_} = 1} (keys %news_status);
	} );
	syslog("\"news, what news?");
      } elsif ($1 eq "pump") {
        ### allow another news item through.
	asAdmin($event->{From}, sub {
          syslog("is decanting an article.");
	  show_news();
	} );
      } else {
	# fallback: try to execute the cmd request as if CJ typed it himself.
	$todo = $1;
	syslog("is being manipulated by $event->{From}");
        ($cmdto = $event->{From}) =~ s/ /_/g ;
        asAdmin($event->{From}, sub {
          do_command($todo, sub {
            foreach (@_) { server("$cmdto;$_"); }
	  } );
	} );
      }
    } elsif ($event->{Body} =~ m:^\s*poll:) {
        $message = get_polling_2k();
  #  } elsif ($event->{Body} =~ m:^eval\s+(.*):) {
  #    ui_output("(" . $event->{From} . " :: " . $event->{Body} . ")\n");
  #    asAdmin($event->{From}, sub {
  #      $retval = eval $1;
  #      server($event->{From} . ":" . "EVAL: " . $retval);
  #    } ) ;
    } elsif ($event->{Body} =~ m:^\s*help\s+stock\s+lookup:i) {
      $message = "stock lookup <string> queries quote.yahoo.com to lookup possible indices for stocks. Try 'stock lookup unified' to test. I'll only return $stock_max_lookup items at a time";
    } elsif ($event->{Body} =~ m:^\s*help\s*stock:i) {
      $message = "stock <Ticker Symbols> displays the latest information available from quote.yahoo.com about the particular symbols. The ticker symbols may be separated by commas or spaces. NB: I just pass along the request. try 'help stock lookup' to find out about stock lookups.";
    } elsif ($event->{Body} =~ m:^\s*help\s*track:i) {
      $message = "I track some stocks in the $stock_disc discussion. 'track list' displays those stocks currently being tracked. 'track clear' stops tracking of all stocks. 'track <Ticker Symbol>' toggles tracking of <Ticker Symbol>. See 'help stock' for more information on ticker symbols.";
    } elsif ($event->{Body} =~ m:^\s*help\s*define:i) {
      $message = "I'm connected to a few online dictionaries, and any define requests are shipped there. Try 'define computer mediated communication' for a little nod to lily, or 'define foldoc' to find out what the FOLDOC is all about. I will check FOLDOC, followed by Webster, followed by a cache of \"local\" definitions. To specify a dictionary, try 'define -webster kiss' vs. 'define -foldoc kiss'.";
    } elsif ($event->{Body} =~ m:^\s*help todo:i) {
      $message = "";
      my $counter = 0; 
      foreach my $todo (@TODO) {
	$todo =~ s/\n/ /g;
	$todo =~ s/\s+/ /g;
	$counter++;
        $message .= "($counter) " . $todo . " ; ";
      }
      if (! $counter) {
	$message = "I have nothing pending on my TODO list.";
      } else {
        chop $message; chop $message; chop $message; 
      }
    } elsif ($event->{Body} =~ m:^\s*help:i) {
      $message = "I'll answer any private questions, and any public questions that you address to me. If you can think of anything interesting I can do, please let $MAINTAINER know. I recognize the following private commands: 'quote', 'stock <stock Ticker>', 'track', 'define', and 'poll' (y2k prez poll). I also respond to 'quote', 'define' and 'buzz' publicly (but only if they begin your send). I also send headline news from CNN to cj-news and a few other discussions. If you talk to me privately, I'll gladly help you work out your problems. Help is also available with 'help stock', 'help track', 'help define', and 'help todo'.";
    } elsif ($event->{Body} =~ /^\s*stock\s+lookup\s+(.*)/i) {
      $stock = $1;
      syslog("looks up symbols for: $1");
      $message = lookup_stock($stock);
   } elsif ($event->{Body} =~ /^\s*stock\s*(.*)/i) {
      @stocks = split(/,\s*|\s+/,$1);
      syslog("gives a stock quote for: @stocks");
      $message = get_stock(@stocks);
    } elsif ($event->{Body} =~ /^\s*track\s*(.*)/i) {
      if ($1 =~ /^\s*clear$/) {
        stock_unload(); #clear current handlers
        undef @stock_tracked;
        syslog("is not tracking any stocks");
        $message = "Stock tracking disabled.";
      } elsif ($1  =~ /^\s*list$/) {
        if (!defined (@stock_tracked) or $#stock_tracked == -1) { 
          $message = "Stock tracking disabled.";
	  syslog("has disabled Stock tracking.");
        } else { 
          $message = "Now tracking @stock_tracked";
          syslog("is now tracking @stock_tracked");
        }
      } else {
        my $stock = $1;
        if (grep (/^$stock$/,@stock_tracked)) {
          $message = "Stopped tracking $stock.";
	  syslog("has stopped tracking $stock.");
          @stock_tracked = grep (!/^$stock$/, @stock_tracked);
        } else {     
          $message = "Started tracking $stock.";
	  syslog("has started tracking $stock.");
          setup_stock_timer($stock);
        }
      }
    } else {
      $message=$eliza->transform($event->{Body});
      syslog("is eliza-ing");
    }
  } else {
    syslog("\@That's wierd. I just got an event of type: $event->{Form}");
  }
  if (defined ($message) and $message ne "") {
    server("$sendlist:$message"); 
  }
  return 1;
}

### GO!

### preload variables
read_files() ;

### Register the CJ event handler
register_eventhandler(Type => "send", Call => \&cj_event);

### Pre-fill the news rack, start the news cycle.
show_news;
if (! defined($news_timer_id)) {
  $news_timer_id = register_timedhandler(Interval => $news_freq, 
                                                  Repeat => 1,
                                                  Call => \&show_news
                                     );
}

### Extension initializations are always TRUE! TRUE, you HEAR ME!
1;
