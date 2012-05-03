#!/usr/bin/env perl

use warnings;
use strict;

require v5.10.0;		# for the 'say' feature
use feature 'say';

use File::Copy qw(copy);
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
use Strings qw($LF
	       $EMPTY_STRING);
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

# All the needed stylesheets exist
my @extensions = ('dco', 'dno', 'voc', 'miz');
foreach my $stylesheet (@STYLESHEETS) {
    my $stylesheet_path = "${STYLESHEET_HOME}/${stylesheet}";
    if (! is_readable_file ($stylesheet_path)) {
	error_message ('The required stylsheet ', $stylesheet, ' could not be found in the directory', "\n", "\n", '  ', $STYLESHEET_HOME, "\n", "\n", 'where we expect to find it (or it does exist but is unreadable).');
	exit 1;
    }
}

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

######################################################################
## Creating the environment and the text
######################################################################

my $tptp_dirname = dirname ($tptp_file);

# XMLize the TPTP file and save it under a temporary file

my $derivation = undef;
if ($opt_style eq 'eprover') {
    $derivation = EproverDerivation->new (path => $tptp_file);
} else {
    print {*STDERR} error_message ('Unknown derivation style \'', $opt_style, '\'.');
    exit 1;
}

$derivation->to_miz ($db,
		     { 'shape' => $opt_nested ? 'nested' : 'flat' });

__END__

=pod

=head1 TSTP2MIZ

tstp2miz - Transform a TSTP derivation into a Mizar article

=head1 SYNOPSIS

tstp2miz.pl [options] [tptp-file]

=head1 OPTIONS

=over 8

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=item B<--verbose>

Say what we're doing.

=item B<--db=DIRECTORY>

By default, results will be saved in a directory whose name is derived
from the name of the supplied Mizar article (stripping the '.miz'
extension, if present).  This option permits saving work to some other
directory.  It is an error if the supplied directory already exists.

=back

=head1 DESCRIPTION

B<tstp2miz.pl> will transform the supplied TPTP file into a
corresponding Mizar article.

=cut
