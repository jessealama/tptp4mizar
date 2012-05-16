#!/usr/bin/env perl

use strict;
use warnings;

require v5.10.0; # for the 'say' feature
use feature 'say';

use IPC::Cmd qw(can_run);
use IPC::Run qw(harness);
use Readonly;
use Getopt::Long;

# Our stuff
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Utils qw(is_readable_file
	     error_message
	     run_harness);

# Strings
Readonly my $SP => q{ };

# Programs
Readonly my $TPTP2X => 'tptp2X';
Readonly my $PROVER9 => 'prover9';
Readonly my $PROOFTRANS => 'prooftrans';

my $opt_man = 0;
my $opt_help = 0;
my $opt_verbose = 0;
my $opt_debug = 0;
my $opt_timeout = 60;

sub process_commandline {
    my $options_ok = GetOptions (
	'timeout=i' => \$opt_timeout,

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
    my @programs = ($PROVER9, $TPTP2X, $PROOFTRANS);
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
my $prooftrans_xml = run_harness (\@prooftrans_xml_call, $prover9_expanded);
my $ivy_proof_object = run_harness (\@prooftrans_ivy_call, $prover9_expanded);

say $prooftrans_xml;

exit 0;

__END__

=pod

=head1 NAME

ivy

=head1 DESCRIPTION

Solve a TPTP problem with Prover9, getting a TPTP-style Ivy derivation
as output (if a solution can be found).

=head1 SEE ALSO

=over 8

=item L<The TPTP and TSTP Quick Guide|http://www.cs.miami.edu/~tptp/TPTP/QuickGuide/>

=item L<"Ivy: A preprocessor and proof checker for first-order logic", by William McCune  and Olga Shumsky|http://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.45.4430>

=back

=cut
