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
	     normalize_variables
	     run_mizar_tool
	     tptp_xmlize
	     apply_stylesheet
	     tptp_fofify);
use TPTPProblem qw(is_valid_tptp_file);
use EproverDerivation;
use VampireDerivation;
use IvyDerivation;

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
Readonly my $EPROVER_STYLESHEET_HOME => "${STYLESHEET_HOME}/eprover";
Readonly my $VAMPIRE_STYLESHEET_HOME => "${STYLESHEET_HOME}/vampire";

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
    'ivy' => 0,
);

sub summarize_styles {
    my $summary = $EMPTY_STRING;
    foreach my $style (sort keys %STYLES) {
	$summary .= '  * ' . colored ($style, $STYLE_COLOR);
    }
    return $summary;
}

sub ensure_tptp_programs_available {
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
my $opt_debug = 0;
my $opt_nested = 0;
my $opt_style = 'tstp';
my $opt_article_name = 'proof';
my $opt_source_article_name = undef;
my $opt_source_tptp = undef;
my $opt_repair = 1;

my $options_ok = GetOptions (
    "db=s"     => \$db,
    "verbose"  => \$verbose,
    'debug' => \$opt_debug,
    'help' => \$help,
    'man' => \$man,
    'nested' => \$opt_nested,
    'style=s' => \$opt_style,
    'article-name=s' => \$opt_article_name,
    'source-article-name=s' => \$opt_source_article_name,
    'source-tptp=s' => \$opt_source_tptp,
    'repair!' => \$opt_repair,
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

if ($opt_debug) {
    $verbose = 1;
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
ensure_tptp_programs_available ();

my $tptp_file = $ARGV[0];

if (! is_readable_file ($tptp_file) ) {
    error_message ('The supplied TPTP file,', "\n", "\n", '  ', $tptp_file, "\n", "\n", 'does not exist, or is unreadable.');
    exit 1;
}

my $tptp_basename = basename ($tptp_file);
my $tptp_sans_extension = strip_extension ($tptp_basename);

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

if (! defined $db) {
    $db = "${tptp_sans_extension}-mizar";
}

if (! -d $db) {
    mkdir $db
	or die error_message ('Unable to make a directory at ', $db, ': ', $!);
}

my $tptp_file_basename = basename ($tptp_file);
my $tptp_file_in_db = "${db}/problem.tptp";
copy ($tptp_file, $tptp_file_in_db)
    or die error_message ('Unable to save a copy of the derivation to', $SP, $db);

# XMLize
my $tptp_xml_in_db = "${db}/${opt_article_name}.xml";
tptp_fofify ($tptp_file_in_db, $tptp_file_in_db);
tptp_xmlize ($tptp_file_in_db, $tptp_xml_in_db);
normalize_variables ($tptp_xml_in_db);

my $sort_tstp_stylesheet = "${TSTP_STYLESHEET_HOME}/sort-tstp.xsl";
my $dependencies_stylesheet = "${TSTP_STYLESHEET_HOME}/tstp-dependencies.xsl";

if ($opt_style ne 'tptp') {

    # Sort
    my $dependencies_str = undef;
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

    apply_stylesheet ($sort_tstp_stylesheet,
		      $tptp_xml_in_db,
		      $tptp_xml_in_db,
		      {
			  'ordering' => $dependencies_token_string,
		      });

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
} elsif ($opt_style eq 'ivy') {
    $derivation = IvyDerivation->new (path => $tptp_xml_in_db);
} else {
    print {*STDERR} error_message ('Unknown derivation style \'', $opt_style, '\'.');
    exit 1;
}

$derivation->to_miz ($db,
		     $opt_article_name,
		     $opt_source_article_name,
		     $opt_source_tptp,
		     { 'shape' => $opt_nested ? 'nested' : 'flat' });

exit 0 if $opt_style eq 'tptp'; # we don't try to check TPTP problems

exit 0 if ! $opt_repair;

my $repair_script = "$RealBin/mrepair.pl";

my $repair_status = system ($repair_script,
			    "--style=${opt_style}",
			    '--debug',
			    "--tptp-proof=${tptp_xml_in_db}",
			    "${db}/text/${opt_article_name}.miz");
my $repair_exit_code = $repair_status >> 8;
if ($repair_exit_code != 0) {
    die error_message ('The repair script did not terminate cleanly.');
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
