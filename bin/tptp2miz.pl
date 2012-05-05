#!/usr/bin/env perl

use warnings;
use strict;

require v5.10.0;		# for the 'say' feature
use feature 'say';

use File::Copy qw(copy move);
use File::Basename qw(basename dirname);
use Getopt::Long;
use Pod::Usage;
use Cwd qw(getcwd);
use Carp qw(croak carp);
use IPC::Run qw(harness);
use IPC::Cmd qw(can_run);
use Readonly;
use charnames qw(:full);
use Regexp::DefaultFlags;
use Term::ANSIColor qw(colored);
use FindBin qw($RealBin);
use Data::Dumper;
use XML::LibXML;

# Our packages
use lib "$RealBin/../lib";
use Utils qw(is_readable_file
	     is_valid_xml_file
	     strip_extension
	     warning_message
	     error_message
	     slurp
	     run_mizar_tool);
use TPTPProblem qw(is_valid_tptp_file);
use EproverDerivation;
use VampireDerivation;
use Xsltproc qw(apply_stylesheet);

# Colors
Readonly my $STYLE_COLOR => 'blue';

# Programs
Readonly my $TPTP4X => 'tptp4X';
Readonly my $GETSYMBOLS => 'GetSymbols';
Readonly my @TPTP_PROGRAMS => (
    $TPTP4X,
    $GETSYMBOLS
);

# Stylesheets
Readonly my $STYLESHEET_HOME => "$RealBin/../xsl";
Readonly my $TSTP_STYLESHEET_HOME => "${STYLESHEET_HOME}/tstp";
Readonly my $TPTP_STYLESHEET_HOME => "${STYLESHEET_HOME}/tptp";
Readonly my $MIZAR_STYLESHEET_HOME => "${STYLESHEET_HOME}/mizar";
Readonly my @STYLESHEETS => (
    'eprover2evl.xsl',
    'eprover2dco.xsl',
    'eprover2dno.xsl',
    'eprover2voc.xsl',
    'pp.xsl',
    'eprover-safe-skolemizations.xsl',
    'clean-eprover.xsl',
    'eprover2the.xsl',
);

# Strings
Readonly my $LF => "\N{LF}";
Readonly my $SP => q{ };
Readonly my $EMPTY_STRING => q{};

# Derivation styles
Readonly my %STYLES => (
    'tptp' => 0,
    'vampire' => 0,
    'eprover' => 0,
    'tstp' => 0,
);

sub summarize_styles {
    my $summary = $EMPTY_STRING;
    foreach my $style (sort keys %STYLES) {
	$summary .= '  * ' . colored ($style, $STYLE_COLOR);
    }
    return $summary;
}

sub ensure_tptp_pograms_available {
    foreach my $program (@TPTP_PROGRAMS) {
	if (! can_run ($program)) {
	    error_message ('The required program ', $program, ' does not appear to be available.');
	    exit 1;
	}
    }
    return;
}

my $help = 0;
my $man = 0;
my $db = undef;
my $verbose = 0;
my $opt_nested = 0;
my $opt_style = 'tptp';

my $options_ok = GetOptions (
    "db=s"     => \$db,
    "verbose"  => \$verbose,
    'help' => \$help,
    'man' => \$man,
    'nested' => \$opt_nested,
    'style=s' => \$opt_style,
);

if (! $options_ok) {
    pod2usage(
	-exitval => 2,
    );
}

if ($help) {
    pod2usage(
	-exitval => 1,
    );
}

if ($man) {
    pod2usage(
	-exitstatus => 0,
	-verbose => 2,
    );
}

if (scalar @ARGV != 1) {
    pod2usage(
	-exitval => 1,
    );
}

if (! defined $STYLES{$opt_style}) {
    my $message = 'Unknown derivation style \'' . $opt_style . '\'.  The available  styles are:' . $LF . $LF;
    $message .= message (summarize_styles ());
    pod2usage (
	-message => error_message ($message),
	-exitval => 1,
    );
}

# Confirm that essential programs are available.
ensure_tptp_pograms_available ();

my $tptp_file = $ARGV[0];

if (! is_readable_file ($tptp_file) ) {
    error_message ('The supplied TPTP file,', "\n", "\n", '  ', $tptp_file, "\n", "\n", 'does not exist, or is unreadable.');
    exit 1;
}

my $tptp_basename = basename ($tptp_file);
my $tptp_sans_extension = strip_extension ($tptp_basename);

my $tptp_short_name = 'article'; # fixed boring name

######################################################################
## Sanity checking: the input TPTP theory file is coherent
######################################################################

# Can TPTP4X handle the file at all?

if (! is_valid_tptp_file ($tptp_file)) {
    error_message ('The supplied TPTP file,', "\n", "\n", '  ', $tptp_file, "\n", "\n", 'is not a well-formed TPTP file.');
    exit 1;
}

if ($verbose) {
    print 'Sanity Check: The given TPTP file is valid according to TPTP4X.', "\n";
}

# # All the needed stylesheets exist
#
#
# We need to put this check elsewhere.
#
# my @extensions = ('dco', 'dno', 'voc', 'miz');
# foreach my $stylesheet (@STYLESHEETS) {
#     my $stylesheet_path = "${STYLESHEET_HOME}/${stylesheet}";
#     if (! is_readable_file ($stylesheet_path)) {
# 	error_message ('The required stylsheet ', $stylesheet, ' could not be found in the directory', "\n", "\n", '  ', $STYLESHEET_HOME, "\n", "\n", 'where we expect to find it (or it does exist but is unreadable).');
# 	exit 1;
#     }
# }

# We need to check that the TPTP theory does not have a predicate
# symbol used as a function symbol, and that arities are distinct for
# different symbols

if (! defined $db) {
    $db = "${tptp_sans_extension}-mizar";
}

if (-e $db) {
    error_message ('The specified directory', "\n", "\n", '  ', $db, "\n", "\n", 'in which we are to save our work already exists.', "\n", 'Please use a different name');
    exit 1;
}

mkdir $db
    or die error_message ('Unable to make a directory at ', $db, ': ', $!);

my $tptp_file_basename = basename ($tptp_file);
my $tptp_file_in_db = "${db}/problem.tptp";
copy ($tptp_file, $tptp_file_in_db)
    or die error_message ('Unable to save a copy of the derivation to', $SP, $db);

# XMLize
my $tptp_xml_in_db = "${db}/problem.xml";
my $tptp4X_status = system ("tptp4X -N -V -c -x -fxml ${tptp_file_in_db} > ${tptp_xml_in_db}");
my $tptp4X_exit_code = $tptp4X_status >> 8;
if ($tptp4X_exit_code != 0) {
    say {*STDERR} error_message ('tptp4X did not terminate cleanly when XMLizing', $SP, $tptp_file_in_db);
}

if ($opt_style ne 'tptp') {

    # Sort
    my $dependencies_str = undef;
    my $dependencies_stylesheet = "${TSTP_STYLESHEET_HOME}/tstp-dependencies.xsl";
    my @xsltproc_deps_call = ('xsltproc', $dependencies_stylesheet, $tptp_xml_in_db);
    my @tsort_call = ('tsort');
    my $sort_harness = harness (\@xsltproc_deps_call,
				'|',
				\@tsort_call,
				'>', \$dependencies_str);
    $sort_harness->start ();
    $sort_harness->finish ();

    my @dependencies = split ($LF, $dependencies_str);
    my $dependencies_token_string = ',' . join (',', @dependencies) . ',';

    my $sort_tstp_stylesheet = "${TSTP_STYLESHEET_HOME}/sort-tstp.xsl";
    my $sorted_tptp_xml_in_db = "${db}/problem.xml.sorted";
    my $xsltproc_sort_status = system ("xsltproc --stringparam ordering '${dependencies_token_string}' ${sort_tstp_stylesheet} ${tptp_xml_in_db} > ${sorted_tptp_xml_in_db}");
    my $xsltproc_sort_exit_code = $xsltproc_sort_status >> 8;
    if ($xsltproc_sort_exit_code != 0) {
	say {*STDERR} error_message ('xsltproc did not exit cleanly sorting', $SP, $tptp_xml_in_db);
	exit 1;
    }
    move ($sorted_tptp_xml_in_db, $tptp_xml_in_db)
	or die error_message ('Unable to overwrite', $SP, $tptp_xml_in_db, $SP, 'by', $SP, $sorted_tptp_xml_in_db);
}

# Normalize names
my $normalize_step_names_stylesheet = "${TSTP_STYLESHEET_HOME}/normalize-step-names.xsl";
apply_stylesheet ($normalize_step_names_stylesheet,
		  $tptp_xml_in_db,
		  $tptp_xml_in_db);

my $tptp_dirname = dirname ($tptp_file);

# XMLize the TPTP file and save it under a temporary file

my $derivation = undef;
if ($opt_style eq 'eprover') {
    $derivation = EproverDerivation->new (path => $tptp_xml_in_db);
} elsif ($opt_style eq 'vampire') {
    $derivation = VampireDerivation->new (path => $tptp_xml_in_db);
} elsif ($opt_style eq 'tstp') {
    $derivation = TSTPDerivation->new (path => $tptp_xml_in_db);
} elsif ($opt_style eq 'tptp') {
    $derivation = TPTPProblem->new (path => $tptp_xml_in_db);
} else {
    print {*STDERR} error_message ('Unknown derivation style \'', $opt_style, '\'.');
    exit 1;
}

$derivation->to_miz ($db,
		     { 'shape' => $opt_nested ? 'nested' : 'flat' });

# Repair the text, if there are any errors
chdir $db
    or die error_message ('Cannot change directory to ', $db);
my $article_in_db = 'text/article.miz';
my $makeenv_ok = run_mizar_tool ('makeenv', $article_in_db);

if (! $makeenv_ok) {
    die error_message ('makeenv did not terminate cleanly working with', $SP, $article_in_db);
}

my $wsmparser_ok = run_mizar_tool ('wsmparser', $article_in_db);

if (! $wsmparser_ok) {
    die error_message ('wsmparser did not terminate cleanly working with', $SP, $article_in_db);
}

my $article_wsx = 'text/article.wsx';

my $verifier_ok = run_mizar_tool ('verifier', $article_in_db);

if ($verifier_ok) {
    exit 0;
}

my $article_err = 'text/article.err';

if (! is_readable_file ($article_err)) {
    die error_message ('The .err file', $SP, $article_err, $SP, 'does not exist, or is unreadable.');
}

# Make a token string out of the errors
my $errs = slurp ($article_err);
$errs =~ s /\N{SPACE}/:/g;
$errs =~ s /\N{LF}/,/g;

my $err_token_string = ',' . $errs;

warn 'error token string: ', $err_token_string;

my $repair_stylesheet = "${MIZAR_STYLESHEET_HOME}/repair.xsl";

# Warning: we are inside $db at this point
my $repair_dir = 'repair';
mkdir $repair_dir
    or die error_message ('Cannot make the repair directory: ', $!);

my $repair_problems = "${repair_dir}/problems.xml";
apply_stylesheet (
    $repair_stylesheet,
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
my $render_tptp_stylesheet = "${TPTP_STYLESHEET_HOME}/render-tptp.xsl";
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
foreach my $problem (@problems) {
    my $problem_name = $problem->exists ('@name') ? $problem->findvalue ('@name') : undef;
    if (! defined $problem_name) {
	die error_message ('We found a problem without a name.');
    }

    my $problem_path = "${repair_dir}/${problem_name}.p";
    my $solution_path = "${repair_dir}/${problem_name}.p.proof.xml";

    if (! is_readable_file ($problem_path)) {
	die error_message ('We failed to generate a plain text TPTP representation for', $SP, $problem_name);
    }

    my @eprove_call = ('eprove', $problem_path);
    my @epclextract_call = ('epclextract', '--tstp-out');
    my @tptp4X_call = ('tptp4X', '-tfofify', '-fxml', '--');

    my $eprover_harness = harness (\@eprove_call,
				   '|',
				   \@epclextract_call,
				   '|',
				   \@tptp4X_call,
				   '>', $solution_path);

    $eprover_harness->start ();
    $eprover_harness->finish ();

}

__END__

=pod

=head1 TPTP2MIZ

tptp2miz - Transform a TSTP derivation into a Mizar article

=head1 SYNOPSIS

tptp2miz.pl [options] [tptp-file]

=head1 OPTIONS

=over 8

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=item B<--verbose>

Say what we're doing.

=item B<--db=DIRECTORY>

By default, results will be saved in a directory whose name is derived from
the name of the supplied TPTP/TSTP file.  This option permits saving work to
some other directory.  It is an error if the supplied directory already
exists.

=item B<--style=TSTP-STYLE>

Use this option to indicate what kind of TPTP problem/TSTP solution one has.
There are four supported options:

=over 8

=item tptp

=item tstp

=item eprover

=item vampire

=back

By default, C<tstp> is used.

=item B<--nested>

Indicate that some high-level grouping should be done among the steps in the
given derivation (if indeed it is a derivation; this option makes sense only
when C<--style> is not C<tptp>).

=back

=head1 DESCRIPTION

B<tptp2miz.pl> will transform the supplied TPTP problem/TSTP derivation file
into a corresponding Mizar article.  It creates a new directory in which the
generated Mizar text ("article") and needed auxiliary files are stored.  The
generated Mizar file will be found under the C<text> subdirectory of the
generated directory under the name C<article.miz>.

=head1 AUTHOR

L<Jesse Alama|jesse.alama@gmail.com>

=head1 ACKNOWLEDGEMENTS

Josef Urban provided the initial inspiration and discussion about this
package.  He has some similar ideas for generating Mizar texts from
non-Mizar derivations: see his
L<ott2miz|https://github.com/JUrban/ott2miz> for some code to
translate Otter proofs to Mizar texts.

=head1 BUGS AND LIMITATIONS

It is known that this program does not always generate Mizar texts that are
Mizar-verifiable.  We are working to provide greater coverage.  In the case
of generic TPTP problems and TSTP derivations, we can make no promise that
the generated text is Mizar-verifiable.  For TSTP derivations emitted by
Vampire and E, though, our aim is to ensure that the generated Mizar text is
acceptable to Mizar.

Please submit bugs/issues to the tptp4mizar issue tracker:

=over 8

L<https://github.com/jessealama/tptp4mizar/issues>

=back

=head1 DEPENDENCIES

Unfortunately this program has a number of dependencies.  It is planned to
provide a web frontend to all this, so that the dependency problem is
eliminated.  But for now, we depend on this:

=head2 Perl dependencies

This program requires several Perl modules.  See CPAN or your package system
for:

=over 8

=item File::Copy

=item File::Basename

=item Getopt::Long

=item Pod::Usage

=item IPC::Run

=item IPC::Cmd

=item Readonly

=item Regexp::DefaultFlags

=item Term::ANSIColor

=item FindBin

=back

=head2 Non-Perl dependencies

This package uses the following programs:

=over 8

=item tptp4X

=item GetSymbols

=item xsltproc

=item xsltxt

=back

=head1 SEE ALSO

=over 8

=item L<The TPTP Homepage|http://www.tptp.org>

=item L<The E Theorem Prover|http://www.eprover.org>

=item L<The Vampire Theorem Prover|http://www.vprover.org>

=back

=head1 LICENSE

Copyright (c) 2012 Jesse Alama (jesse.alama@gmail.com).  All rights
reserved.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See L<perlartistic>.  This
program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.

=cut
