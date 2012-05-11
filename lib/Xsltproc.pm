package Xsltproc;

use base qw(Exporter);
use warnings;
use strict;
use Carp qw(croak carp confess);
use IPC::Run qw(harness);
use Data::Dumper;

use Utils qw(is_readable_file);

our @EXPORT = qw(apply_stylesheet);

sub apply_stylesheet {

    my ($stylesheet, $document, $result_path, $parameters_ref) = @_;

    if (! defined $stylesheet) {
	croak ('Error: please supply a stylesheet.');
    }

    if (! defined $document) {
	croak ('Error: please supply a document.');
    }

    my %parameters = defined $parameters_ref ? %{$parameters_ref}
	                                     : ()
					     ;


    if (! is_readable_file ($stylesheet)) {
	croak ('Error: there is no stylesheet at ', $stylesheet, '.');
    }

    if (! is_readable_file ($document)) {
	croak ('Error: there is no file at ', $document, '.');
    }

    my @xsltproc_call = ('xsltproc');
    foreach my $parameter (keys %parameters) {
	my $value = $parameters{$parameter};
	push (@xsltproc_call, '--stringparam', $parameter, $value);
    }

    push (@xsltproc_call, $stylesheet);
    push (@xsltproc_call, $document);

    my $xsltproc_out = '';
    my $xsltproc_err = '';

    my $xsltproc_harness = harness (\@xsltproc_call,
				    '>', \$xsltproc_out,
				    '2>', \$xsltproc_err);

    $xsltproc_harness->start ();
    $xsltproc_harness->finish ();
    my $xsltproc_result = ($xsltproc_harness->result)[0];

    if ($xsltproc_result != 0) {
	croak ('Error: xsltproc did not exit cleanly when applying the stylesheet', "\n", "\n", '  ', $stylesheet, "\n", "\n", 'to', "\n", "\n", '  ', $document, ' .  Its exit code was ', $xsltproc_result, '.', "\n", "\n",  'Here is the error output: ', "\n", $xsltproc_err);
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
