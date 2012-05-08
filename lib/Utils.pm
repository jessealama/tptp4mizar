package Utils;

use strict;
use warnings;

use Carp qw(carp confess croak);
use Regexp::DefaultFlags;
use Term::ANSIColor qw(colored);
use Readonly;
use Data::Dumper;
use charnames qw(:full);
use IPC::Run qw(harness);
use IPC::Cmd qw(can_run);

Readonly my $EMPTY_STRING => q{};
Readonly my $SP => q{ };
Readonly my $COLON => q{:};
Readonly my $LF => "\N{LF}";

Readonly my $ERROR_COLOR => 'red';
Readonly my $WARNING_COLOR => 'yellow';

use base qw(Exporter);
our @EXPORT_OK = qw(error_message
		    warning_message
		    strip_extension
		    is_readable_file
		    is_valid_xml_file
		    slurp
		    run_mizar_tool);

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

sub is_valid_xml_file {
    my $path = shift;

    if (! -e $path) {
	return 0;
    }

    if (! -r $path) {
	return 0;
    }

    my $xmllint_status = system ("xmllint --noout ${path} > /dev/null 2>&1");
    my $xmllint_exit_code = $xmllint_status >> 8;

    return $xmllint_exit_code == 0 ? 1 : 0;

}

sub run_mizar_tool {
    my $tool = shift;
    my $article = shift;

    if (! can_run ($tool)) {
	die error_message ($tool, $SP, 'is not executable.');
    }

    my $tool_out = $EMPTY_STRING;
    my $tool_err = $EMPTY_STRING;
    my @tool_call = ($tool, '-q', '-l', $article);
    my $tool_harness = harness (\@tool_call,
				'>', \$tool_out,
				'2>', \$tool_err);

    $tool_harness->start ();
    $tool_harness->finish ();

    my $exit_code = ($tool_harness->results ())[0];

    return $exit_code == 0 ? 1 : 0;

}

sub slurp {
    my $path_or_fh = shift;

    open (my $fh, '<', $path_or_fh)
	or die 'Error: unable to open the file (or filehandle) ', $path_or_fh, '.';

    my $contents;
    { local $/; $contents = <$fh>; }

    close $fh
	or die 'Error: unable to close the file (or filehandle) ', $path_or_fh, '.';

    if (wantarray) {
	return split ($LF, $contents);
    } else {
	return $contents;
    }
}

1;
__END__
