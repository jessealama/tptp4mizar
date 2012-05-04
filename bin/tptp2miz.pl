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

# Our packages
use lib "$RealBin/../lib";
use Utils qw(is_readable_file
	     is_valid_xml_file
	     strip_extension
	     warning_message
	     error_message);
use Colors;
use TPTPProblem qw(is_valid_tptp_file);
use EproverDerivation;
use VampireDerivation;

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
