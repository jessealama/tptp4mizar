#!/usr/bin/env perl

use strict;
use warnings;

require v5.10.0; # for the 'say' feature
use feature 'say';

use Getopt::Long;
use IPC::Cmd qw(can_run);
use IPC::Run qw(harness);
use Readonly;
use File::Temp qw(tempfile);

use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Utils qw(sort_tstp_solution
	     tptp_xmlize
	     apply_stylesheet
	     sort_tstp_solution
	     normalize_tstp_steps);

my $opt_man = 0;
my $opt_help = 0;

Readonly my $EMPTY_STRING => q{};

sub process_commandline {

    my $options_ok = GetOptions (
	'help' => \$opt_help,
	'man' => \$opt_man,
    );

    if (! $options_ok) {
	pod2usage (
	    -exitval => 1,
	);
    }

    if ($opt_help) {
	pod2usage(
	    -exitstatus => 0,
	    -verbose => 2,
	);
    }

    if ($opt_man) {
	pod2usage(
	    -exitstatus => 0,
	    -verbose => 2,
	);
    }

    if (scalar @ARGV > 1) {
	pod2usage (
	    -exitval => 1,
	);
    }

    return;

}

process_commandline ();

my $ivy_file = undef;
if (scalar @ARGV == 1) {
    my $first_arg = $ARGV[0];
    if (! -e $first_arg) {
	say {*STDERR} 'Error: ', $first_arg, ' does not exist.';
	exit 1;
    }
    if (-d $first_arg) {
	say {*STDERR} 'Error: ', $first_arg, ' is a directory.';
	exit 1;
    }
    if (! -r $first_arg) {
	say {*STDERR} 'Error: ', $first_arg, ' is unreadable.';
	exit 1;
    }
    $ivy_file = $first_arg;
} else {
    my $content = undef;
    { local $/; $content = <ARGV>; }
    (my $tmp_fh, my $tmp_path) = tempfile ();
    say {$tmp_fh} $content;
    close $tmp_fh;
    $ivy_file = $tmp_path;
}


my $ivy_to_tstp_lisp = "$RealBin/../lisp/ivy2tstp.lisp";

my @ccl_call = ('ccl',
		'--batch',
		'--load', $ivy_to_tstp_lisp,
		'--eval', '(print-ivy2tstp #p"' . $ivy_file . '")',
	        '--eval', '(ccl:quit)');
my $ccl_output = $EMPTY_STRING;
my $ccl_err = $EMPTY_STRING;
my $ccl_harness = harness (\@ccl_call,
			   '>', \$ccl_output,
			   '2>', \$ccl_err);

$ccl_harness->start ();
$ccl_harness->finish ();

my $ccl_exit_code = ($ccl_harness->results)[0];

if ($ccl_exit_code != 0) {
    say {*STDERR} 'ccl did not exit cleanly; its exit code was ', $ccl_exit_code, '.';
    say {*STDERR} 'Here is its error output:';
    say {*STDERR} $ccl_err;
    exit 1;
}

my $ivy_xml = tptp_xmlize ($ccl_output);
my $sorted_ivy_xml = sort_tstp_solution ($ivy_xml);
my $normalized_steps_xml = normalize_tstp_steps ($sorted_ivy_xml);

my $render_tptp_stylesheet = "$RealBin/../xsl/tptp/render-tptp.xsl";

my $rendered = apply_stylesheet ($render_tptp_stylesheet,
				 $normalized_steps_xml,
				 undef,
				 {
				     'tstp' => '1',
				 }
			     );

print $rendered;

__END__

=pod

=head1 NAME

ivy2tstp

=head1 SYNOPSIS

ivy2tstp [ --help | --man ] # get help; any other arguments will be ignored

ivy2tstp # no arguments; read from standard input

ivy2tstp IVY-PROOF-OBJECT # one argument; path to a file containing an Ivy proof object

=head1 DESCRIPTION

ivy2tstp produces a TSTP solution file

=head1 SEE ALSO

=over 8

=item L<The TPTP and TSTP Quick Guide|http://www.cs.miami.edu/~tptp/TPTP/QuickGuide/>

=item L<"Ivy: A preprocessor and proof checker for first-order logic", by William McCune  and Olga Shumsky|http://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.45.4430>

=back

=cut
