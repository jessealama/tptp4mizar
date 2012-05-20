#!/usr/bin/env perl

use strict;
use warnings;

require v5.10.0; # for the 'say' feature
use feature 'say';

use IPC::Cmd qw(can_run);
use IPC::Run qw(harness);
use Readonly;
use Getopt::Long;
use Pod::Usage;

# Our stuff
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Utils qw(is_readable_file
	     error_message
	     run_harness);
use Xsltproc qw(apply_stylesheet);

# Strings
Readonly my $SP => q{ };

# Programs
Readonly my $TPTP2X => 'tptp2X';
Readonly my $PROVER9 => 'prover9';
Readonly my $PROOFTRANS => 'prooftrans';
Readonly my $XSLTPROC => 'xsltproc';

my $opt_man = 0;
my $opt_help = 0;
my $opt_verbose = 0;
my $opt_debug = 0;
my $opt_timeout = 60;
my $opt_format = 'tptp';

sub process_commandline {
    my $options_ok = GetOptions (
	'timeout=i' => \$opt_timeout,
	'format=s' => \$opt_format,

    );

    if (! $options_ok) {
	pod2usage (
	    -exitval => 2,
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

    if (scalar @ARGV != 1) {
	pod2usage (
	    -exitval => 2,
	);
    }

    if ($opt_format ne 'lisp' && $opt_format ne 'tptp') {
	pod2usage (
	    -message => error_message ('For the format option only two values are acceptable: \'lisp\' and \'tptp\'.'),
	    -exitval => 1,
	);
    }

    # debug implies verbose
    if ($opt_debug) {
	$opt_verbose = 1;
    }

    my $problem_file = $ARGV[0];

    if (! is_readable_file ($problem_file)) {
	die error_message ('The given TPTP problem file', $SP, $problem_file, $SP, 'does not exist or is unreadable.');
    }

    return;

}

sub ensure_stuff_is_runnable {
    my @programs = ($PROVER9, $TPTP2X, $PROOFTRANS, $XSLTPROC);
    foreach my $program (@programs) {
	if (! can_run ($program)) {
	    say {*STDERR} error_message ('We require', $SP, $program, $SP, 'but it could not be found.');
	    exit 1;
	}
    }
    return;
}

process_commandline ();

ensure_stuff_is_runnable ();

my $problem_file = $ARGV[0];

my @tptp2X_call = ($TPTP2X, '-tstdfof', '-fprover9', '-q2', '-d-', $problem_file);
my @prover9_call = ($PROVER9);
my @prooftrans_expand_call = ($PROOFTRANS, 'expand', 'renumber');
my @prooftrans_xml_call = ($PROOFTRANS, 'xml');
my @prooftrans_ivy_call = ($PROOFTRANS, 'ivy');

my $tptp2X_out = run_harness (\@tptp2X_call);
my $prover9_out = run_harness (\@prover9_call, $tptp2X_out);
my $prover9_expanded = run_harness (\@prooftrans_expand_call, $prover9_out);
my $ivy_proof_object = run_harness (\@prooftrans_ivy_call, $prover9_expanded);

if ($opt_format eq 'lisp') {
    print $ivy_proof_object;
    exit $?;
}

my $prooftrans_xml = run_harness (\@prooftrans_xml_call, $prover9_expanded);

my $prover9_to_tptp_stylesheet = "$RealBin/../xsl/prover9/prover92tptp.xsl";
my $render_tptp_stylesheet = "$RealBin/../xsl/tptp/render-tptp.xsl";

my $prover9_tptp_xml = apply_stylesheet ($prover9_to_tptp_stylesheet,
					 $prooftrans_xml);

my $tptp = apply_stylesheet ($render_tptp_stylesheet,
			     $prover9_tptp_xml,
			     undef,
			     {
				 'tstp' => '1',
			     }
			 );


my $ivy_to_tstp_script = "$RealBin/ivy2tstp.pl";

if (! can_run ($ivy_to_tstp_script)) {
    say {*STDERR} error_message ('Cannot run the Ivy-to-TSTP script (we expected to find it at', $SP, $ivy_to_tstp_script, ')');
    exit 1;
}

my @ivy_to_tstp_call = ($ivy_to_tstp_script);
my $ivy_tstp = run_harness (\@ivy_to_tstp_call, $ivy_proof_object);

print $ivy_tstp;

__END__

=pod

=head1 NAME

ivy

=head1 SYNOPSIS

ivy [ --help | --man ]

ivy [ --timeout=N ] TPTP-FILE

=head1 DESCRIPTION

Solve a TPTP problem with Prover9, getting a TPTP-style Ivy derivation
as output (if a solution can be found).

=head1 SEE ALSO

=over 8

=item L<The TPTP and TSTP Quick Guide|http://www.cs.miami.edu/~tptp/TPTP/QuickGuide/>

=item L<"Ivy: A preprocessor and proof checker for first-order logic", by William McCune  and Olga Shumsky|http://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.45.4430>

=back

=cut
