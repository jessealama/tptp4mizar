#!/usr/bin/env perl

use strict;
use warnings;

require v5.10.0; # for the 'say' feature
use feature 'say';

use Carp qw(croak confess);
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
use Utils qw(is_readable_file
	     error_message
	     slurp
	     run_mizar_tool
	     normalize_variables
	     tptp_fofify
	     tptp_xmlize
	     apply_stylesheet
	     sort_tstp_solution);

# Strings
Readonly my $EMPTY_STRING => q{};
Readonly my $LF => "\N{LF}";
Readonly my $SP => q{ };

# Stylesheets
Readonly my $STYLESHEET_HOME => "$RealBin/../xsl";
Readonly my $TSTP_STYLESHEET_HOME => "${STYLESHEET_HOME}/tstp";
Readonly my $IVY_STYLESHEET_HOME => "${STYLESHEET_HOME}/ivy";
Readonly my $TPTP_STYLESHEET_HOME => "${STYLESHEET_HOME}/tptp";
Readonly my $MIZAR_STYLESHEET_HOME => "${STYLESHEET_HOME}/mizar";
Readonly my $EPROVER_STYLESHEET_HOME => "${STYLESHEET_HOME}/eprover";
Readonly my $VAMPIRE_STYLESHEET_HOME => "${STYLESHEET_HOME}/vampire";

# Colors
Readonly my $STYLE_COLOR => 'blue';

# Derivation styles
Readonly my %STYLES => (
    # 'tptp' => 0,
    # 'vampire' => 0,
    'eprover' => 0,
    'tstp' => 0,
    # 'tstp' => 0,
    'ivy' => 0,
);

sub summarize_styles {
    my $summary = $EMPTY_STRING;
    foreach my $style (sort keys %STYLES) {
	$summary .= '  * ' . colored ($style, $STYLE_COLOR) . "\N{LF}";
    }
    return $summary;
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
	my $message = 'Unknown derivation style \'' . $opt_style . '\'.  The available styles are:' . $LF . $LF;
	$message .= summarize_styles ();
	pod2usage (
	    -exitval => 1,
	    -message => error_message ($message),
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

my $source_xml_path = File::Spec->rel2abs ($opt_tptp_proof);

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
my $article_evl = "text/${article_basename}.evl";

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
if (! -d $repair_dir) {
    mkdir $repair_dir
	or die error_message ('Cannot make the repair directory: ', $!);
}

my $repair_problems = "${repair_dir}/problems.xml";
apply_stylesheet (
    $mizar_repair_stylesheet,
    $article_wsx,
    $repair_problems,
    {
	'errors' => $err_token_string,
    }
);

# Extract the problems, render them as TPTP files, solve with Prover9
my $xml_parser = XML::LibXML->new ();
my $problems_doc = $xml_parser->parse_file ($repair_problems);

(my $problems_root) = $problems_doc->findnodes ('problems');

my $num_problems = $problems_root->findvalue ('count (*)');

my @problems = $problems_root->findnodes ('*');

my $render_tptp_stylesheet = "${TPTP_STYLESHEET_HOME}/render-tptp.xsl";
my $ivy_script = "$RealBin/ivy.pl";
my $tptp_to_mizar_script = "$RealBin/tptp2miz.pl";
my $compress_mizar_script = "$RealBin/mcompress.pl";
foreach my $problem (@problems) {
    my $problem_name = $problem->exists ('@name') ? $problem->findvalue ('@name') : undef;
    if (! defined $problem_name) {
	die error_message ('We found a problem without a name.');
    }

    my $problem_xml_path = "${repair_dir}/${problem_name}.p.xml";

    my $node_string = $problem->toString ();

    open (my $problem_fh, '>', $problem_xml_path)
	or die error_message ('Cannot open an output filehandle for', $SP, $problem_xml_path, ':', $SP, $!);
    say {$problem_fh} '<?xml version="1.0" ?>';
    say {$problem_fh} $node_string;
    close $problem_fh
	or die error_message ('Unable to close the output filehandle for', $SP, $problem_xml_path);

    my $problem_path = "${repair_dir}/${problem_name}.p";
    my $problem_tmp_path = "${repair_dir}/${problem_name}.p.tmp";

    normalize_variables ($problem_xml_path);

    apply_stylesheet ($render_tptp_stylesheet,
		      $problem_xml_path,
		      $problem_path);

    # fofify
    tptp_fofify ($problem_path, $problem_path);
    tptp_xmlize ($problem_path, $problem_xml_path);

    my $ivy_solution_path = "${repair_dir}/${problem_name}.ivy.tptp";

    my @ivy_call = ($ivy_script, $problem_path);

    my $ivy_errs = $EMPTY_STRING;
    my $ivy_harness = harness (\@ivy_call,
			       '>', $ivy_solution_path,
			       '2>', \$ivy_errs);

    print 'Repairing', $SP, $problem_name, $SP, 'with Prover9...';

    $ivy_harness->start ();
    $ivy_harness->finish ();

    my $ivy_exit_code = ($ivy_harness->results)[0];

    if ($ivy_exit_code != 0) {
	confess error_message ('The Ivy script did not terminate cleanly when working with', $SP, $problem_path);
    }

    say 'done.';
    print 'Mizarizing Prover9\'s refutation...';

    $ivy_solution_path = File::Spec->rel2abs ($ivy_solution_path);
    my $repaired_db = "${repair_dir}/${problem_name}";
    my $source_article_name = basename ($source_xml_path, '.xml');

    my @tptp_to_miz_call = ($tptp_to_mizar_script,
			    '--style=ivy',
			    "--db=${cwd}",
			    "--article-name=${problem_name}",
			    "--source-tptp=${source_xml_path}",
			    "--source-article-name=${source_article_name}",
			    $ivy_solution_path);

    my $tptp_to_miz_out = $EMPTY_STRING;
    my $tptp_to_miz_errs = $EMPTY_STRING;
    my $tptp_to_miz_harness = harness (\@tptp_to_miz_call,
				       '>', \$tptp_to_miz_out,
				       '2>', \$tptp_to_miz_errs);

    $tptp_to_miz_harness->start ();
    $tptp_to_miz_harness->finish ();

    my $tptp_to_miz_exit_code = ($tptp_to_miz_harness->results)[0];

    if ($tptp_to_miz_exit_code != 0) {
	confess error_message ('The TPTP-to-Mizar script did not terminate cleanly when working with', $SP, $ivy_solution_path, '. Here is its error output:', $LF, $tptp_to_miz_errs);
	exit 1;
    }

    say 'done.';

    print 'Compressing the Mizarization of', $SP, $problem_name, '...';

    my $problem_miz = "text/${problem_name}.miz";

    my @compress_call = ($compress_mizar_script, $problem_miz);

    my $compress_out = $EMPTY_STRING;
    my $compress_errs = $EMPTY_STRING;
    my $compress_harness = harness (\@compress_call);

    $compress_harness->start ();
    $compress_harness->finish ();

    my $compress_exit_code = ($compress_harness->results)[0];

    if ($compress_exit_code != 0) {
	confess error_message ('The Mizar compressor script did not terminate cleanly when working with', $SP, $problem_name, '.  Here is its error output:', $LF, $compress_errs);
    }

    print 'Exporting', $SP, $problem_name, $SP, 'to the local database...';

    my $exporter_ok = run_mizar_tool ('exporter', $problem_miz);

    if (! $exporter_ok) {
	die error_message ('The exporter did not exit cleanly working with', $SP, $problem_miz);
    }

    my $transfer_ok = run_mizar_tool ('transfer', $problem_miz);

    if (! $transfer_ok) {
	die error_message ('The Mizar transfer utility did not exit cleanly working with', $SP, $problem_miz);
    }

    say 'done.';

}

my $patch_stylesheet = "$RealBin/../xsl/mizar/patch.xsl";
apply_stylesheet ($patch_stylesheet,
		  $article_wsx,
		  $article_wsx,
		  {
		      'errors' => $err_token_string,
		  }
	      );

my @problem_names = map { scalar $_->findvalue ('@name') } @problems;

my $problems_as_tokens = ',' . join (',', @problem_names) . ',';

my $add_to_evl_stylesheet = "$RealBin/../xsl/mizar/add-theorems-to-evl.xsl";
apply_stylesheet ($add_to_evl_stylesheet,
		  $article_evl,
		  $article_evl,
		  {
		      'new-theorems' => $problems_as_tokens,
		  }
	      );

my $pp_stylesheet = "$RealBin/../xsl/mizar/pp.xsl";
apply_stylesheet ($pp_stylesheet,
		  $article_wsx,
		  $article_miz,
		  {
		      'indenting' => '1',
		      'evl' => $article_evl,
		  }
	      );

# Weird: Mizar is fussy about line and column info in the .evl
unlink $article_evl;

$makeenv_ok = run_mizar_tool ('makeenv', $article_miz);

if (! $makeenv_ok) {
    say {*STDERR} error_message ('makeenv did not exit cleanly working with', $SP, $article_miz);
    exit 1;
}

my $verifier_ok = run_mizar_tool ('verifier', $article_miz);

if (! $verifier_ok) {
    say {*STDERR} error_message ('makeenv did not exit cleanly working with', $SP, $article_miz);
    exit 1;
}

# Compress the final .miz
my $compress_script = "$RealBin/mcompress.pl";
my @compress_call = ($compress_script, $article_miz);
my $compress_harness = harness (\@compress_call);
$compress_harness->start ();
$compress_harness->finish ();

my $compress_exit_code = ($compress_harness->results)[0];

if ((! defined $compress_exit_code) || $compress_exit_code != 0) {
    say {*STDERR} error_message ('The compression script did not exit cleanly working with', $SP, $article_miz, '. The exit code was', $SP, $compress_exit_code, '.');
}

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

=item eprover

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
