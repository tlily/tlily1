register_eventhandler(Type => 'userinput',
		      Call => sub {
			  my($e, $h) = @_;
			  $e->{ToUser} = 0 if ($e =~ /^\S*[;:]/);
		      });
