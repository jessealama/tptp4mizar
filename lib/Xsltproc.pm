package Xsltproc;

use base qw(Exporter);
use warnings;
use strict;
use Carp qw(croak carp confess);
use IPC::Run qw(harness);
use Data::Dumper;
use Readonly;
use charnames qw(:full);
use Regexp::DefaultFlags;
use Utils qw(is_readable_file
	     is_file);

our @EXPORT = qw(apply_stylesheet);

Readonly my $LF => "\N{LF}";
Readonly my $SP => q{ };
Readonly my $EMPTY_STRING => q{};

sub apply_stylesheet {

    my ($stylesheet, $document, $result_path, $parameters_ref) = @_;

    if (! defined $stylesheet) {
	confess ('Error: please supply a stylesheet.');
    }

    if (! defined $document) {
	confess ('Error: please supply a document.');
    }

    my %parameters = defined $parameters_ref ? %{$parameters_ref}
	                                     : ()
					     ;


    if (! is_readable_file ($stylesheet)) {
	confess ('Error: there is no stylesheet at ', $stylesheet, '.');
    }

    my @xsltproc_call = ('xsltproc');
    foreach my $parameter (keys %parameters) {
	my $value = $parameters{$parameter};
	push (@xsltproc_call, '--stringparam', $parameter, $value);
    }

    push (@xsltproc_call, $stylesheet);

    push (@xsltproc_call, '-');

    my $xsltproc_out = '';
    my $xsltproc_err = '';

    my $xsltproc_harness = undef;
    if (is_file ($document)) {
	$xsltproc_harness = harness (\@xsltproc_call,
				     '<', $document,
				     '>', \$xsltproc_out,
				     '2>', \$xsltproc_err);
    } else {
	$xsltproc_harness = harness (\@xsltproc_call,
				     '<', \$document,
				     '>', \$xsltproc_out,
				     '2>', \$xsltproc_err);
    }

    $xsltproc_harness->start ();
    $xsltproc_harness->finish ();
    my $xsltproc_result = ($xsltproc_harness->result)[0];

    if ($xsltproc_result != 0) {
	if (scalar keys %parameters == 0) {
	    if (defined $result_path) {
		confess ('Error: xsltproc did not exit cleanly when applying the stylesheet', $LF, $LF, $SP, $SP, $stylesheet, $LF, $LF, 'to', $LF, $SP, $SP, $document, $LF, $LF, 'to generate', $LF, $LF, $SP, $SP, $result_path, $LF, $LF, 'Its exit code was ', $xsltproc_result, '. No stylesheet parameters were given.  Here is the error output: ', "\n", $xsltproc_err);
	    } else {
		confess ('Error: xsltproc did not exit cleanly when applying the stylesheet', "\n", "\n", '  ', $stylesheet, $LF, $LF, 'to', $LF, $LF, $SP, $SP, $document, $LF, 'Its exit code was ', $xsltproc_result, '. No stylesheet parameters were given.  Here is the error output: ', "\n", $xsltproc_err);
	    }
	} else {

	    my $parameters_message = $EMPTY_STRING;
	    foreach my $parameter (sort keys %parameters) {
		my $value = $parameters{$parameter};
		$parameters_message .= $SP . $SP . "${parameter} ==> ${value}" . $LF;
	    }

	    if (defined $result_path) {
		confess ('Error: xsltproc did not exit cleanly when applying the stylesheet', "\n", "\n", '  ', $stylesheet, "\n", "\n", 'to', "\n", "\n", '  ', $document, $LF, $LF, 'so that we could generate', $LF, $LF, $SP, $SP, $result_path, $LF, $LF, 'Its exit code was ', $xsltproc_result, '. These were the stylesheet parameters:', $LF, $LF, $parameters_message, $LF, 'Here is the error output: ', $LF, $LF, $xsltproc_err, $LF);
	    } else {
		confess ('Error: xsltproc did not exit cleanly when applying the stylesheet', "\n", "\n", '  ', $stylesheet, "\n", "\n", 'to', "\n", "\n", '  ', $document, $LF, $LF, 'Its exit code was ', $xsltproc_result, '. These were the stylesheet parameters:', $LF, $LF, $parameters_message, $LF, 'Here is the error output: ', $LF, $LF, $xsltproc_err, $LF);
	    }

	}

    }

    if (defined $result_path) {
	open (my $result_fh, '>', $result_path)
	    or confess 'Unable to open an output filehandle for ', $result_path, '.';
	print {$result_fh} $xsltproc_out
	    or confess 'Unable to print to the output filehandle for ', $result_path, '.';
	close $result_fh
	    or confess 'Unable to close the output filehandle for ', $result_path, '.';
	return $xsltproc_out;
    } elsif (wantarray) {
	# carp 'HEY: wantarray; xsltproc output is ', $xsltproc_out;
	chomp $xsltproc_out;
	my @answer = split (/\n/, $xsltproc_out);
	return @answer;
    } else {
	# carp 'HEY: do not wantarray';
	return $xsltproc_out;
    }

}

1; # I'm OK, you're OK
__END__
