#!/usr/bin/env perl

use strict;
use warnings;

require v5.10.0; # for the 'say' feature
use feature 'say';

use Data::Dumper;
use Pod::Usage;
use Getopt::Long;
use Regexp::DefaultFlags;
use Readonly;
use charnames qw(:full);
use File::Spec;
use File::Basename qw(basename dirname);
use Cwd qw(getcwd);
use XML::LibXML;
use IPC::Run qw(harness);
use Term::ANSIColor qw(colored);

use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Xsltproc qw(apply_stylesheet);
use Utils qw(is_readable_file
	     error_message
	     slurp
	     run_mizar_tool
	     normalize_variables);

# Strings
Readonly my $EMPTY_STRING => q{};
Readonly my $LF => "\N{LF}";
Readonly my $SP => q{ };

# Stylesheets
Readonly my $STYLESHEET_HOME => "$RealBin/../xsl";
Readonly my $TSTP_STYLESHEET_HOME => "${STYLESHEET_HOME}/tstp";
Readonly my $TPTP_STYLESHEET_HOME => "${STYLESHEET_HOME}/tptp";
Readonly my $MIZAR_STYLESHEET_HOME => "${STYLESHEET_HOME}/mizar";
Readonly my $EPROVER_STYLESHEET_HOME => "${STYLESHEET_HOME}/eprover";
Readonly my $VAMPIRE_STYLESHEET_HOME => "${STYLESHEET_HOME}/vampire";

# Colors
Readonly my $STYLE_COLOR => 'blue';

# Derivation styles
Readonly my %STYLES => (
    # 'tptp' => 0,
    'vampire' => 0,
    'eprover' => 0,
    # 'tstp' => 0,
    # 'ivy' => 0,
);

sub summarize_styles {
    my $summary = $EMPTY_STRING;
    foreach my $style (sort keys %STYLES) {
	$summary .= '  * ' . colored ($style, $STYLE_COLOR);
    }
    return $summary;
}

my $sort_tstp_stylesheet = "${TSTP_STYLESHEET_HOME}/sort-tstp.xsl";
my $dependencies_stylesheet = "${TSTP_STYLESHEET_HOME}/tstp-dependencies.xsl";

sub sort_tstp_solution {
    my $solution = shift;

    # Sort
    my $dependencies_str = undef;
    my @xsltproc_deps_call = ('xsltproc', $dependencies_stylesheet, $solution);
    my @tsort_call = ('tsort');
    my $sort_harness = harness (\@xsltproc_deps_call,
				'|',
				\@tsort_call,
				'>', \$dependencies_str);
    $sort_harness->start ();
    $sort_harness->finish ();

    my @dependencies = split ($LF, $dependencies_str);
    my $dependencies_token_string = ',' . join (',', @dependencies) . ',';

    apply_stylesheet ($sort_tstp_stylesheet,
		      $solution,
		      $solution,
		      { 'ordering' => $dependencies_token_string });
}

my $opt_help = 0;
my $opt_man = 0;
my $opt_debug = 0;
my $opt_verbose = 0;
my $opt_style = undef;
my $opt_tptp_proof = undef;

sub process_commandline {

    my $commandline_ok
	= GetOptions (
	    'help' => \$opt_help,
	    'man' => \$opt_man,
	    'debug' => \$opt_debug,
	    'verbose' => \$opt_verbose,
	    'style=s' => \$opt_style,
	    'tptp-proof=s' => \$opt_tptp_proof,
	);

    if (! $commandline_ok) {
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

    if (! defined $STYLES{$opt_style}) {
	my $message = 'Unknown derivation style \'' . $opt_style . '\'.  The available  styles are:' . $LF . $LF;
	$message .= summarize_styles ();
	pod2usage (
	    -message => error_message ($message),
	    -exitval => 1,
	);
    }

    # debug implies verbose
    if ($opt_debug) {
	$opt_verbose = 1;
    }

    my $article = $ARGV[0];

    if (! is_readable_file ($article)) {
	die error_message ('The given file', $SP, $article, $SP, 'does not exist or is unreadable.');
    }

}

process_commandline ();

my $article = $ARGV[0];
my $article_full = File::Spec->rel2abs ($article);
my $article_dirname = dirname ($article_full);

# Go to the right directory
chdir $article_dirname
    or die error_message ('Unable to change directory to', $SP, $article_dirname, ':', $SP, $!);
chdir '..'
    or die error_message ('Unable to change to the parent directory of', $SP, $article_dirname, ':', $SP, $!);

my $cwd = getcwd ();
my $article_basename = basename ($article_full, '.miz');
my $article_miz = "text/${article_basename}.miz";
my $article_err = "text/${article_basename}.err";
my $article_wsx = "text/${article_basename}.wsx";

my $makeenv_ok = run_mizar_tool ('makeenv', $article_miz);

if (! $makeenv_ok) {
    die error_message ('makeenv did not exit cleanly working with', $SP, $article_miz, $SP, 'in the directory', $SP, $cwd);
}

my $wsmparser_ok = run_mizar_tool ('wsmparser', $article_miz);

if (! $wsmparser_ok) {
    die error_message ('wsmparser did not exit cleanly working with', $SP, $article_miz, $SP, 'in the directory', $SP, $cwd);
}

run_mizar_tool ('verifier', $article_miz);

if (! is_readable_file ($article_err)) {
    die error_message ('verifier did not generate a .err file (or the file is somehow unreadable).');
}

if (-z $article_err) {
    if ($opt_verbose) {
	say 'Article is OK according to the Mizar verifier.';
    }
    exit 0;
}

# Make a token string out of the errors
my $errs = slurp ($article_err);
$errs =~ s /\N{SPACE}/:/g;
$errs =~ s /\N{LF}/,/g;

my $err_token_string = ',' . $errs;

# warn 'error token string: ', $err_token_string;

my $mizar_repair_stylesheet = "${MIZAR_STYLESHEET_HOME}/repair.xsl";

# Warning: we are inside $db at this point
my $repair_dir = 'repair';
mkdir $repair_dir
    or die error_message ('Cannot make the repair directory: ', $!);

my $repair_problems = "${repair_dir}/problems.xml";
apply_stylesheet (
    $mizar_repair_stylesheet,
    $article_wsx,
    $repair_problems,
    {
	'errors' => $err_token_string,
    }
);

# Extract the problems
my $xml_parser = XML::LibXML->new ();
my $problems_doc = $xml_parser->parse_file ($repair_problems);

(my $problems_root) = $problems_doc->findnodes ('problems');

my $num_problems = $problems_root->findvalue ('count (*)');

my @problems = $problems_root->findnodes ('*');

my $render_tptp_stylesheet = "${TPTP_STYLESHEET_HOME}/render-tptp.xsl";
foreach my $problem (@problems) {
    my $problem_name = $problem->exists ('@name') ? $problem->findvalue ('@name') : undef;
    if (! defined $problem_name) {
	die error_message ('We found a problem without a name.');
    }

    my $problem_path = "${repair_dir}/${problem_name}.p.xml";

    my $node_string = $problem->toString ();

    open (my $problem_fh, '>', $problem_path)
	or die error_message ('Cannot open an output filehandle for', $SP, $problem_path, ':', $SP, $!);
    say {$problem_fh} '<?xml version="1.0" ?>';
    say {$problem_fh} $node_string;
    close $problem_fh
	or die error_message ('Unable to close the output filehandle for', $SP, $problem_path);
}

# Render the problems as plain text TPTP files
foreach my $problem (@problems) {
    my $problem_name = $problem->exists ('@name') ? $problem->findvalue ('@name') : undef;
    if (! defined $problem_name) {
	die error_message ('We found a problem without a name.');
    }

    my $problem_xml_path = "${repair_dir}/${problem_name}.p.xml";
    my $problem_path = "${repair_dir}/${problem_name}.p";
    my $problem_tmp_path = "${repair_dir}/${problem_name}.p.tmp";

    if (! is_readable_file ($problem_xml_path)) {
	die error_message ('We failed to generate the XML TPTP representation for', $SP, $problem_name);
    }

    apply_stylesheet ($render_tptp_stylesheet,
		      $problem_xml_path,
		      $problem_tmp_path);

    # fofify
    my $fofify_status = system ("tptp4X -tfofify ${problem_tmp_path} > ${problem_path}");
    my $fofify_exit_code = $fofify_status >> 8;
    if ($fofify_exit_code != 0) {
	die error_message ('tptp4X did not exit cleanly fofifying ', $problem_tmp_path);
    }

    unlink $problem_tmp_path;

}

# Solve each of the problems with E
my $skolemized_problem_stylesheet = "${EPROVER_STYLESHEET_HOME}/skolemized-problem.xsl";
my $existential_stylesheet = "${TPTP_STYLESHEET_HOME}/existential.xsl";
my $eprover_normalize_step_names_stylesheet
    = "${EPROVER_STYLESHEET_HOME}/normalize-step-names.xsl";
my $prefix_skolem_stylesheet = "${EPROVER_STYLESHEET_HOME}/prefix-skolems.xsl";
foreach my $problem (@problems) {
    my $problem_name = $problem->exists ('@name') ? $problem->findvalue ('@name') : undef;
    if (! defined $problem_name) {
	die error_message ('We found a problem without a name.');
    }

    my $problem_path = "${repair_dir}/${problem_name}.p";

    if (! is_readable_file ($problem_path)) {
	die error_message ('We failed to generate a plain text TPTP representation for', $SP, $problem_name);
    }

    my $eprover_solution_path = "${repair_dir}/${problem_name}.p.eprover-proof";
    my $eprover_xml_solution_path = "${repair_dir}/${problem_name}.p.eprover-proof.xml";

    my @eprove_call = ('eprove', $problem_path);
    my @epclextract_call = ('epclextract', '--tstp-out');

    my $eprover_harness = harness (\@eprove_call,
				   '|',
				   \@epclextract_call,
				   '>', $eprover_solution_path);

    $eprover_harness->start ();
    $eprover_harness->finish ();

    # XMLize the E proof
    my @tptp4X_call = ('tptp4X', '-fxml', $eprover_solution_path);
    my $tptp4X_harness = harness (\@tptp4X_call,
				  '>', $eprover_xml_solution_path);
    $tptp4X_harness->start ();
    $tptp4X_harness->finish ();


    # Sort
    sort_tstp_solution ($eprover_xml_solution_path);
    normalize_variables ($eprover_xml_solution_path);
    apply_stylesheet ($eprover_normalize_step_names_stylesheet,
    		      $eprover_xml_solution_path,
    		      $eprover_xml_solution_path);
    apply_stylesheet ($prefix_skolem_stylesheet,
		      $eprover_xml_solution_path,
		      $eprover_xml_solution_path,
		  {
		      'prefix' => $problem_name,
		  });

    # Now extract a clausified problem that we will later give to prover9
    my $skolemized_xml_problem = "${repair_dir}/${problem_name}-clausified.p.xml";
    apply_stylesheet ($skolemized_problem_stylesheet,
		      $eprover_xml_solution_path,
		      $skolemized_xml_problem,
		      {
			  'skolem-prefix' => $problem_name,
		      });

    normalize_variables ($skolemized_xml_problem);

    # Sanity check: there had better not be any existential
    # quantifiers in the TPTP problem we just created
    my $exists_existential = eval { apply_stylesheet ($existential_stylesheet,
    						      $skolemized_xml_problem) };
    if (! defined $exists_existential) {
    	die error_message ('There is at least one existential quantifier appearing in ', $skolemized_xml_problem, ', but to proceed there cannot be any.');
    }

    my $skolemized_problem = "${repair_dir}/${problem_name}-clausified.p";
    apply_stylesheet ($render_tptp_stylesheet,
		      $skolemized_xml_problem,
		      $skolemized_problem);

    # Now extract the initial part of E's proof consisting just of the
    # clausification part
    my $clausification_subproof_xml = "${repair_dir}/${problem_name}-clausification.xml";
    apply_stylesheet ($skolemized_problem_stylesheet,
		      $eprover_xml_solution_path,
		      $clausification_subproof_xml,
		      {
			  'only-skolemized-part' => '1',
			  'tstp' => '1',
			  'skolem-prefix' => $problem_name,
		      });
    sort_tstp_solution ($clausification_subproof_xml);
    normalize_variables ($clausification_subproof_xml);
    my $clausification_subproof = "${repair_dir}/${problem_name}-clausification.p";
    apply_stylesheet ($render_tptp_stylesheet,
		      $clausification_subproof_xml,
		      $clausification_subproof);

}

# Now solve each of the problems with Prover9, and get an Ivy proof object
my $ivy_to_tstp_script = "$RealBin/ivy2tstp.pl";
foreach my $problem (@problems) {
    my $problem_name = $problem->findvalue ('@name');
    my $skolemized_problem_path = "${repair_dir}/${problem_name}-clausified.p";
    my $ivy_solution_path = "${repair_dir}/${problem_name}-clausified.ivy-proof";
    my $ivy_xml_solution_path = "${repair_dir}/${problem_name}-clausified.ivy-proof.xml";
    my $ivy_errs = $EMPTY_STRING;

    my @fofify_call = ('tptp4X', '-tfofify', $skolemized_problem_path);
    my @tptp2X_call = ('tptp2X', '-tstdfof', '-fprover9', '-q2', '-d-', '-');
    my @prover9_call = ('prover9');
    my @prooftrans_expand_call = ('prooftrans', 'expand', 'renumber');
    my @prooftrans_ivy_call = ('prooftrans', 'ivy');

    my $prover9_harness = harness (\@fofify_call,
				   '|',
				   \@tptp2X_call,
				   '|',
				   \@prover9_call,
				   '|',
				   \@prooftrans_expand_call,
				   '|',
				   \@prooftrans_ivy_call,
				   '>', $ivy_solution_path,
				   '2>', \$ivy_errs);

    $prover9_harness->start ();
    $prover9_harness->finish ();

    my @ivy_to_tstp_call = ($ivy_to_tstp_script);
    my @tptp4X_call = ('tptp4X', '-tfofify', '-fxml', '--');

    my $ivy_to_tstp_harness = harness (\@ivy_to_tstp_call,
				       '<', $ivy_solution_path,
				       '|',
				       \@tptp4X_call,
				       '>', $ivy_xml_solution_path);

    $ivy_to_tstp_harness->start ();
    $ivy_to_tstp_harness->finish ();


}

# # Shift the skolem functions
# my $prefix_skolem_stylesheet = "${EPROVER_STYLESHEET_HOME}/prefix-skolems.xsl";
# foreach my $problem (@problems) {
#     my $problem_name = $problem->findvalue ('@name');

#     my $eprover_solution_path = "${repair_dir}/${problem_name}.p.eprover-proof.xml";

#     apply_stylesheet ($prefix_skolem_stylesheet,
# 		      $eprover_solution_path,
# 		      $eprover_solution_path,
# 		  {
# 		      'prefix' => $problem_name,
# 		  });

# }

# Repair the proofs
my @eprover_clausification_xmls = glob "${repair_dir}/*-clausification.xml";
my @ivy_proof_xmls = glob "${repair_dir}/*-clausified.ivy-proof.xml";

# warn 'eprover clausification xmls:', $LF, Dumper (@eprover_clausification_xmls);
# warn 'ivy proof xmls:', $LF, Dumper (@ivy_proof_xmls);

my @solution_names = map { $_->findvalue ('@name') } @problems;

my $solutions_token_string = ',' . join (',', @solution_names) . ',';

my $repair_stylesheet = undef;
if ($opt_style eq 'vampire') {
    $repair_stylesheet = "${VAMPIRE_STYLESHEET_HOME}/repair-vampire.xsl";
} elsif ($opt_style eq 'eprover') {
    $repair_stylesheet = "${EPROVER_STYLESHEET_HOME}/repair-eprover.xsl";
} else {
    die error_message ('Unsuported proof style "', $opt_style, '".');
}

if (! is_readable_file ($repair_stylesheet)) {
    die error_message ('The repair stylesheet does not exist at the expected location (', $repair_stylesheet, '), or it is unreadable.');
}

my $eprover_to_voc_stylesheet = "${EPROVER_STYLESHEET_HOME}/eprover2voc.xsl";
my $eprover_to_dco_stylesheet = "${EPROVER_STYLESHEET_HOME}/eprover2dco.xsl";
my $eprover_to_dno_stylesheet = "${EPROVER_STYLESHEET_HOME}/eprover2dno.xsl";
my $eprover_to_the_stylesheet = "${EPROVER_STYLESHEET_HOME}/eprover2the.xsl";
foreach my $problem (@problems) {
    my $problem_name = $problem->findvalue ('@name');
    my $solution_path = "${repair_dir}/${problem_name}.p.eprover-proof.xml";
    my $solution_voc = "dict/${problem_name}.voc";
    my $solution_dco = "prel/${problem_name}.dco";
    my $solution_dno = "prel/${problem_name}.dno";
    my $solution_the = "prel/${problem_name}.the";

    apply_stylesheet ($eprover_to_voc_stylesheet,
		      $solution_path,
		      $solution_voc,
		      {
			  'only-skolems' => '1',
		      }
		  );

    apply_stylesheet ($eprover_to_dco_stylesheet,
		      $solution_path,
		      $solution_dco,
		      {
			  'only-skolems' => '1',
			  'article' => $problem_name,
		      }
		  );

    apply_stylesheet ($eprover_to_dno_stylesheet,
		      $solution_path,
		      $solution_dno,
		      {
			  'only-skolems' => '1',
			  'article' => $problem_name,
		      }
		  );

    apply_stylesheet ($eprover_to_the_stylesheet,
		      $solution_path,
		      $solution_the,
		      {
			  'prel-directory' => File::Spec->rel2abs ('prel'),
			  'article' => $problem_name,
			  'only-skolems' => '1',
			  'reference-dco' => 'article',
		      }
		  );

}

# Normalize varibles in the original problem
normalize_variables ('problem.xml');

# Let's try the evl
my $repaired_wsx = 'text/repaired.wsx';
my $clausifications_token_string = ',' . join (',', map { basename ($_, '-clausification.xml') . ':' . File::Spec->rel2abs ($_) } @eprover_clausification_xmls) . ',';
my $herbrand_proofs_token_string = ',' . join (',', map { basename ($_, '-clausified.ivy-proof.xml') . ':' . File::Spec->rel2abs ($_) } @ivy_proof_xmls) . ',';
my $vampire_to_evl_stylesheet = "${VAMPIRE_STYLESHEET_HOME}/vampire2evl.xsl";
apply_stylesheet ($vampire_to_evl_stylesheet,
		  'problem.xml',
		  'text/repaired.evl',
		  {
		      'external-proofs' => $solutions_token_string,
		      'article' => 'ARTICLE',
		  });


if ($opt_debug) {
    warn 'clausifications:', $LF, $clausifications_token_string;
    warn 'herbrand-proofs:', $LF, $herbrand_proofs_token_string;
}

apply_stylesheet ($repair_stylesheet,
		  'problem.xml',
		  $repaired_wsx,
		  {
		      'clausifications' => $clausifications_token_string,
		      'herbrand-proofs' => $herbrand_proofs_token_string,
		      'article' => 'ARTICLE',
		  });

# Generate the .miz for the repaired .wsx
my $repaired_miz = 'text/repaired.miz';
my $pp_stylesheet = "${MIZAR_STYLESHEET_HOME}/pp.xsl";
apply_stylesheet ($pp_stylesheet,
		  $repaired_wsx,
		  $repaired_miz,
		  {
		      'evl' => File::Spec->rel2abs ('text/repaired.evl'),
		      'indenting' => '1',
		  });


__END__

=pod

=head1 NAME

mrepair - Repair failed steps in TPTP-to-Mizar proofs with E and Prover9/Ivy

=head1 SYNOPSIS

mrepair [ --help | --man ]

mrepair --style=STYLE --tptp-proof=PROOF MIZAR-ARTICLE

=head1 DESCRIPTION

Given a TPTP derivation and a Mizar article, C<mrepair> attempts to
patch the C<*4> errors in the given article.  A copy of the given
Mizar article will be made; repairs will then be placed into a file of
the same name (i.e., the original Mizar article will be overwritten).

The C<--style> option is used to indicate the style of the given TPTP
proof.  Supported styles are:

=over 8

=item vampire

=back

The patch the *4 "holes", we use E to clausify the problem and then
use Prover9/Ivy to generate a derivation for the clausified problem.

=head1 AUTHOR

L<Jesse Alama|jesse.alama@gmail.com>

=head1 SEE ALSO

=over 8

=item <The Mizar homepage|http://mizar.org/>

=item <The E theorem prover|http://www.eprover.org>

=item <The Vampire theorem prover|http://www.vprover.org>

=item L<"Ivy: A preprocessor and proof checker for first-order logic", by William McCune  and Olga Shumsky|http://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.45.4430>

=back

=cut
