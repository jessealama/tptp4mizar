#!/usr/bin/env perl

use strict;
use warnings;

require v5.10.0; # for the 'say' feature
use feature 'say';

use Carp qw(croak confess carp);
use Data::Dumper;
use IPC::Cmd qw(can_run);
use IPC::Run qw(harness);
use Readonly;
use Getopt::Long;
use Pod::Usage;
use charnames qw(:full);
use List::MoreUtils qw(pairwise first_index all);
use Perl6::Slurp;

# Our stuff
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Utils qw(is_readable_file
	     error_message
	     run_harness
	     tptp_xmlize
	     tptp_fofify
	     apply_stylesheet
	     normalize_variables);

# Strings
Readonly my $SP => q{ };
Readonly my $LF => "\N{LF}";
Readonly my $EMPTY_STRING => q{};

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
	'debug' => \$opt_debug,
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

    if (scalar @ARGV > 1) {
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

    if (scalar @ARGV == 1) {
	my $problem_file = $ARGV[0];
	if (! is_readable_file ($problem_file)) {
	    die error_message ('The given TPTP problem file', $SP, $problem_file, $SP, 'does not exist or is unreadable.');
	}
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

sub equal_attributes {
    my $attr_1 = shift;
    my $attr_2 = shift;

    if (defined $attr_1 && defined $attr_2) {
	my $attr_1_name = $attr_1->nodeName;
	my $attr_2_name = $attr_2->nodeName;

	if ($attr_1_name eq $attr_2_name) {
	    my $attr_1_value = $attr_1->getValue ();
	    my $attr_2_value = $attr_2->getValue ();
	    return ($attr_1_value eq $attr_2_value);
	} else {
	    return 0;
	}
    } elsif ((! defined $attr_1) && (! defined $attr_2)) {
	return 1;
    } else {
	return 0;
    }
}

sub equal_nodes {
    my $node_1 = shift;
    my $node_2 = shift;

    my $node_1_name = $node_1->nodeName;
    my $node_2_name = $node_2->nodeName;

    if ($node_1_name eq $node_2_name) {
	my @node_1_children = $node_1->childNodes;
	my @node_2_children = $node_2->childNodes;
	if (scalar @node_1_children == scalar @node_2_children) {
	    my @node_1_attrs = $node_1->attributes;
	    my @node_2_attrs = $node_2->attributes;
	    if (scalar @node_1_attrs == scalar @node_2_attrs) {
		my @attr_comparison = pairwise { equal_attributes ($a, $b) }
		    @node_1_attrs, @node_2_attrs;
		if (all { $_ ? 1 : 0 } @attr_comparison) {
		    my @children_comparison = pairwise { equal_nodes ($a, $b) }
			@node_1_children, @node_2_children;
		    if (all { $_ ? 1 : 0 } @children_comparison) {
			return 1;
		    } else {
			return 0;
		    }
		} else {
		    return 0;
		}
	    } else {
		return 0;
	    }
	} else {
	    return 0;
	}
    } else {
	return 0;
    }
}

sub equal_formula_nodes {
    my $node_1 = shift;
    my $node_2 = shift;

    (my $node_1_formula_proper) = $node_1->findnodes ('*[1]');
    (my $node_2_formula_proper) = $node_2->findnodes ('*[1]');

    return equal_nodes ($node_1_formula_proper,
			$node_2_formula_proper);
}

my $render_tptp_stylesheet = "$RealBin/../xsl/tptp/render-tptp.xsl";
my $conjecture_stylesheet = "$RealBin/../xsl/tptp/conjecture.xsl";
my $ignore_axioms_stylesheet = "$RealBin/../xsl/tptp/ignore-axioms.xsl";

sub merge_prover9_solutions {
    my $original_problem_xml = shift;
    my $clausification_xml = shift;
    my $refutation_xml = shift;

    my $normalized_clausification_xml = normalize_variables ($clausification_xml);

    my $no_axioms_clausification_xml
	= apply_stylesheet ($ignore_axioms_stylesheet,
			    $normalized_clausification_xml);

    my $parser = XML::LibXML->new ();

    # Extract the conjecture from the original problem

    my $conjecture_xml = apply_stylesheet ($conjecture_stylesheet,
					   $original_problem_xml);

    my $problem_doc = $parser->parse_string ($original_problem_xml);
    my $clausification_doc = $parser->parse_string ($normalized_clausification_xml);
    my $refutation_doc = $parser->parse_string ($refutation_xml);

    my %refutation_to_clausification = ();
    my @refutation_axiom_nodes
	= $refutation_doc->findnodes ('tstp/formula[@status = "axiom"]');
    my @clausification_nodes = $clausification_doc->findnodes ('tstp/formula');

    # Look up each of the axioms appearing in the refutation to find
    # out its name in the clausification
    foreach my $refutation_axiom_node (@refutation_axiom_nodes) {
	my $axiom_name = $refutation_axiom_node->findvalue ('@name');
	my $matching_clausification_index = first_index
	    { equal_formula_nodes ($_, $refutation_axiom_node) } @clausification_nodes;
	if ($matching_clausification_index < 0) {
	    carp 'We did not find a match for the clausification axiom \'', $axiom_name, '\'.';
	} else {
	    my $matching_clausification_node
		= $clausification_nodes[$matching_clausification_index];
	    my $matching_name = $matching_clausification_node->findvalue ('@name');
	    $refutation_to_clausification{$axiom_name} = $matching_name;
	}
    }

    # Rewrite justifications in the refutation part
    my $replacements = $EMPTY_STRING;
    foreach my $axiom_name (keys %refutation_to_clausification) {
	my $clausification_name = $refutation_to_clausification{$axiom_name};
	$replacements .= ",${axiom_name}:${clausification_name}";
    }
    $replacements = ($replacements eq $EMPTY_STRING ? ',' : $replacements) . ',';

    my $rename_justifications_stylesheet = "$RealBin/../xsl/tstp/rename-justifications.xsl";

    my $replaced_refutation
	= apply_stylesheet ($rename_justifications_stylesheet,
			    $refutation_xml,
			    undef,
			    {
				'replacements' => $replacements,
			    });

    my $axiom_free_refutation = apply_stylesheet ($ignore_axioms_stylesheet,
						  $replaced_refutation);

    my $conjecture_tptp = apply_stylesheet ($render_tptp_stylesheet,
					    $conjecture_xml);
    my $problem_tptp = apply_stylesheet ($render_tptp_stylesheet,
					 $original_problem_xml);
    my $clausification_tptp = apply_stylesheet ($render_tptp_stylesheet,
						$no_axioms_clausification_xml);
    my $refutation_tptp = apply_stylesheet ($render_tptp_stylesheet,
					    $axiom_free_refutation);

    return "${conjecture_tptp}${clausification_tptp}${refutation_tptp}";

}

process_commandline ();

ensure_stuff_is_runnable ();

my $problem = undef;

if (scalar @ARGV == 1) {
    $problem = slurp ($ARGV[0]);
} else {
    $problem = slurp (\*ARGV);
}

my $problem_xml = tptp_xmlize ($problem);

my @prover9_call = ($PROVER9);
my @prooftrans_expand_call = ($PROOFTRANS);
my @prooftrans_xml_call = ($PROOFTRANS, 'xml');
my @prooftrans_ivy_call = ($PROOFTRANS, 'renumber', 'ivy');

my $tptp_to_prover9_stylesheet = "$RealBin/../xsl/prover9/tptp2prover9.xsl";

my $prover9_problem = apply_stylesheet ($tptp_to_prover9_stylesheet,
					$problem_xml);

if ($opt_debug) {
    warn 'prover9 problem =', $LF, $prover9_problem;
}

my $prover9_out = run_harness (\@prover9_call, $prover9_problem);
my $prover9_expanded = run_harness (\@prooftrans_expand_call, $prover9_out);
my $ivy_proof_object = run_harness (\@prooftrans_ivy_call, $prover9_expanded);

if ($opt_format eq 'lisp') {
    print $ivy_proof_object;
    exit $?;
}

# Extract the clausification part of the proof

my $prooftrans_xml = run_harness (\@prooftrans_xml_call, $prover9_out);

if ($opt_debug) {
    warn 'prover9 output =', $LF, $prover9_out;
    warn 'prooftrans xml =', $LF, $prooftrans_xml;
}

my $prover9_to_tptp_stylesheet = "$RealBin/../xsl/prover9/prover92tptp.xsl";
my $clausification_stylesheet = "$RealBin/../xsl/prover9/clausification.xsl";
my $clausification_prooftrans_xml = apply_stylesheet ($clausification_stylesheet,
						      $prooftrans_xml);
my $clausification_tptp_xml = apply_stylesheet ($prover9_to_tptp_stylesheet,
						$clausification_prooftrans_xml);

# fofify
my $clausification_tptp = apply_stylesheet ($render_tptp_stylesheet,
					    $clausification_tptp_xml);

if ($opt_debug) {
    warn 'clausification tptp = ', $LF, $clausification_tptp;
#    warn 'clausification tptp xml = ', $LF, $clausification_tptp_xml;
}

$clausification_tptp = tptp_fofify ($clausification_tptp);
$clausification_tptp_xml = tptp_xmlize ($clausification_tptp);

# Now extract the resolution proof proper

my $ivy_to_tstp_script = "$RealBin/ivy2tstp.pl";

if (! can_run ($ivy_to_tstp_script)) {
    say {*STDERR} error_message ('Cannot run the Ivy-to-TSTP script (we expected to find it at', $SP, $ivy_to_tstp_script, ')');
    exit 1;
}

my @ivy_to_tstp_call = ($ivy_to_tstp_script, '--format=xml');
my $ivy_tstp_xml = run_harness (\@ivy_to_tstp_call, $ivy_proof_object);

my $normalize_step_names_stylesheet = "$RealBin/../xsl/tstp/normalize-step-names.xsl";
my $prefixed_ivy_tstp_xml = apply_stylesheet
    ($normalize_step_names_stylesheet,
     $ivy_tstp_xml,
     undef,
     {
	 'step-prefix' => 'ivy_refutation_step',
     });

my $merged_solution = merge_prover9_solutions ($problem_xml,
					       $clausification_tptp_xml,
					       $prefixed_ivy_tstp_xml);



print $merged_solution;

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
