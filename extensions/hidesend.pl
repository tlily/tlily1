# $Header: /data/cvs/tlily/extensions/hidesend.pl,v 1.2 1998/05/29 05:12:27 mjr Exp $
register_eventhandler(Type => 'userinput',
		      Call => sub {
			  my($e, $h) = @_;
			  $e->{ToUser} = 0 if ($e =~ /^\S*[;:]/);
		      });
