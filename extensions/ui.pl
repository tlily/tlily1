# -*- Perl -*-
# $Header: /data/cvs/tlily/extensions/ui.pl,v 2.1 1998/10/25 00:12:21 josh Exp $

my @ui_list = ("default");
my %ui_type;
my %routes;
my %handler_types;

load();

sub load {
    register_user_command_handler('ui', \&ui_command);
    register_help_short('ui', "multi-UI support commands");
    register_help_long('ui', "
Tigerlily supports the notion of multiple \"UI\" modules.  Typically, these
would be used to provide multiple windows on the screen.  This command is the
interface to creating windows and deciding which events go to which window.

Usage: %ui
       %ui list
       %ui add \\<name\\> [\\<type\\>]
       %ui remove \\<name\\>
       %ui route list
       %ui route [type \\<type\\>] [form \\<type\\>] to \\<target\\>

Example: 
       %ui add privates
       %ui route type send form private to privates

       (now all private sends to to the \"privates\" window)
");


}
    
sub unload {
    foreach (@ui_list) {
	next if ($_ eq "default");
	ui_end($_);
    }    
}

sub ui_command {
    $args="@_";

    if ($args =~ /^add (\S+)\s+(.*)/) {
	new_ui($1,$2);
    } elsif ($args =~ /^add (\S+)/) {
	new_ui($1);  
    } elsif ($args eq "" or $args =~ /^list/) {
	if (@ui_list) {
	    ui_output(sprintf("%-10.10s %s","Target","Type"));
	    ui_output(sprintf("%-10.10s %s","-" x 10, "-" x 15));
	    foreach (@ui_list) {
		ui_output(sprintf("%-10.10s %s",$_,$ui_type{$_}));
	    }
	} else {
	    ui_output("(no ui modules are loaded?!!)");
	}
    } elsif ($args =~ /^remove (\S+)/) {
	ui_end($1);
	my @new;
	foreach (@ui_list) {
	    push @new,$_ unless ($_ eq $1);
	}
	@ui_list=@new;
    } elsif ($args =~ /^route list/) {
	ui_output(sprintf("%-15.15s %-15.15s %s","Type","Form","Target"));
	ui_output(sprintf("%-15.15s %-15.15s %s","-" x 15,"-" x 15,"-" x 15));
	
	my $type;
	foreach $type (sort keys %routes) {
	    my $form;
	    foreach $form (sort keys %{$routes{$type}}) {
		ui_output(sprintf("%-15.15s %-15.15s %s",$type,$form,$routes{$type}{$form}));
	    }
	}	
    } elsif ($args =~ /^route/) {
	$args =~ s/^route //g;
	($type)  = ($args =~ /type (\S+)/);
	$args =~ s/type (\S+)//g;
	($form)  = ($args =~ /form (\S+)/);
	$args =~ s/form (\S+)//g;
	($target)= ($args =~ /to (\S+)/);
	$args =~ s/to (\S+)//g;
	
	if ($args =~ /\S/) {
	    ui_output("(unknown arguments \"$args\" to \"%ui route\" command - see %help %ui)");
	}

	$routes{$type}{$form}=$target;

	if (! $handler_types{$type} and $type) {
	    register_eventhandler(Type => $type,
				  Call => \&ui_mux);
	    $handler_types{$type}=1;
	}	

	$type="[all]" unless $type;
	$form="[all]" unless $form;
	$target="[all]" unless $target;

	ui_output("(added UI route: type=$type, form=$form, target=$target)");

    } else {
	ui_output("(unknown command - see %help %ui)");
    }

    return 0;    
}

sub ui_mux($$) {
    my($event,$handler) = @_;

    my $type;
    foreach $type (sort keys %routes) {
	if ($event->{Type} eq $type || (! $type)) {
	    my $form;
	    foreach $form (sort keys %{$routes{$type}}) {	    
		if ($event->{Form} eq $form || (! $form)) {
		    $event->{Target} = $routes{$type}{$form};
		    return 0;
		}
	    }	   
	}
    }

    return 0;
}

sub new_ui {
    my ($target,$type)=@_;

    $type ||= "OutputWindow";	

    ui_start($target,$type);
    push @ui_list,$target;
    $ui_type{$target}=$type;
}

1;
