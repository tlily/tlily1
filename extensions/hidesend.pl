# $Header: /data/cvs/tlily/extensions/hidesend.pl,v 2.1 1998/06/12 08:56:35 albert Exp $
register_eventhandler(Type => 'userinput',
		      Call => sub {
			  my($e, $h) = @_;
			  $e->{ToUser} = 0 if ($e =~ /^\S*[;:]/);
		      });
