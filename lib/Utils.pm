package Utils;

use base qw(Exporter);
our @EXPORT_OK = qw(error_message
		    warning_message
		    strip_extension
		    is_readable_file);

use Colors qw($ERROR_COLOR $WARNING_COLOR);

sub error_message {
    return message_with_colored_prefix ('Error', $ERROR_COLOR, @_);
}

sub warning_message {
    return message_with_colored_prefix ('Warning', $WARNING_COLOR, @_);
}

sub is_readable_file {
    my $file = shift;
    return (-e $file && ! -d $file && -r $file);
}

sub message_with_colored_prefix {
    my $prefix = shift;
    my $color = shift;
    my @message_parts = @_;

    my $message = join ($EMPTY_STRING, @message_parts);
    if ($message eq $EMPTY_STRING) {
	say {*STDERR} colored ($prefix, $color), $COLON, $SP, '(no message is available)';
    } else {
	say {*STDERR} colored ($prefix, $color), $COLON, $SP, $message;
    }

    return;
}

sub strip_extension {
    my $path = shift;
    return $path =~ / (.+) [.][^.]+ \z / ? $1 : $path;
}

1;
__END__
