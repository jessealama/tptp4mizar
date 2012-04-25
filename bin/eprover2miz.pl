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

# Strings
Readonly my $EMPTY_STRING => q{};
Readonly my $SP => q{ };
Readonly my $COLON => q{:};

# Programs
Readonly my $TPTP4X => 'tptp4X';
Readonly my $GETSYMBOLS => 'GetSymbols';
Readonly my @TPTP_PROGRAMS => (
    $TPTP4X,
    $GETSYMBOLS
);

# Stylesheets
Readonly my $STYLESHEET_HOME => "$RealBin/../xsl";
Readonly my $TPTP2VOC_STYLESHEET => "${STYLESHEET_HOME}/eprover2voc.xsl";
Readonly my $TPTP2MIZ_STYLESHEET => "${STYLESHEET_HOME}/eprover2miz.xsl";
Readonly my @STYLESHEETS => (
    'eprover2evl.xsl',
    'eprover2dco.xsl',
    'eprover2dno.xsl',
    'eprover2voc.xsl',
    'pp.xsl',
    'eprover-safe-skolemizations.xsl',
    'clean-eprover.xsl',
);

# Colors
Readonly my $ERROR_COLOR => 'red';
Readonly my $WARNING_COLOR => 'yellow';

sub ensure_readable_file {
    my $file = shift;
    return (-e $file && ! -d $file && -r $file);
}

sub message_with_colored_prefix {
    my $prefix = shift;
    my $color = shift;
    my @message_parts = @_;

    my $message = join ($EMPTY_STRING, @message_parts);
    if ($message eq $EMPTY_STRING) {
	say {*STDERR} colored ($prefix, $color), $COLON, $SP, '(no message is available)';
    } else {
	say {*STDERR} colored ($prefix, $color), $COLON, $SP, $message;
    }

    return;
}

sub error_message {
    return message_with_colored_prefix ('Error', $ERROR_COLOR, @_);
}

sub warning_message {
    return message_with_colored_prefix ('Warning', $WARNING_COLOR, @_);
}

sub strip_extension {
    my $path = shift;
    return $path =~ / (.+) [.][^.]+ \z / ? $1 : $path;
}

sub is_valid_tptp_file {
    my $path = shift;

    my @tptp4x_call = ($TPTP4X, '-N', '-c', '-x', $path);
    my $tptp4x_out = $EMPTY_STRING;
    my $tptp4x_err = $EMPTY_STRING;
    my $tptp4x_harness = harness (\@tptp4x_call,
				  '>', \$tptp4x_out,
				  '2>', \$tptp4x_err);

    $tptp4x_harness->start ();
    $tptp4x_harness->finish ();

    my $tptp4x_exit_code = $tptp4x_harness->result (0);

    return ($tptp4x_exit_code == 0 ? 1 : 0);
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

my $options_ok = GetOptions (
    "db=s"     => \$db,
    "verbose"  => \$verbose,
    'help' => \$help,
    'man' => \$man,
    'nested' => \$opt_nested,
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

# Confirm that essential programs are available.
ensure_tptp_pograms_available ();

my $tptp_file = $ARGV[0];

if (! ensure_readable_file ($tptp_file) ) {
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
    if (! ensure_readable_file ($stylesheet_path)) {
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

my @subdirs = ('text', 'prel', 'dict');

# Save a copy of the input TPTP file
my $tptp_file_in_miz_db = "${db}/${tptp_basename}";
copy ($tptp_file, $tptp_file_in_miz_db)
    or croak ('Error: unable to copy the given TPTP file to the new Mizar db (', $db, '): ', $!);

# XMLize the TPTP file and save it under a temporary file

my $tptp_xml = "${db}/${tptp_basename}.xml";
my $tptp4X_xmlize_status
    = system ("tptp4X -N -V -c -x -fxml $tptp_file > $tptp_xml 2> /dev/null");
my $tptp4X_xmlize_exit_code = $tptp4X_xmlize_status >> 8;
if ($tptp4X_xmlize_exit_code != 0) {
    croak ('Error: tptp4X did not exit cleanly when XMLizing the TPTP file at', "\n", "\n", '  ', $tptp_file, "\n", "\n", 'Its exit code was ', $tptp4X_xmlize_exit_code, '.');
}

# Sanity check: tptp4X generated a readable XML file

if (! -e $tptp_xml) {
    croak ('Error: tptp4X did not generate an XML version of the TPTP file at ', "\n", "\n", $tptp_file);
}

if (! -r $tptp_xml) {
    croak ('Error: the XML reformatting of', "\n", "\n", $tptp_file, "\n", "\n", 'generated by tptp4X is not readable.');
}

my $xmllint_status = system ("xmllint --noout $tptp_xml > /dev/null 2>&1");
my $xmllint_exit_code = $xmllint_status >> 8;

if ($xmllint_exit_code != 0) {
    croak ('Error: tptp4X failed to generate a valid XML document corresponding to the TPTP file at', "\n", "\n", '  ', $tptp_file);
}

my $safe_skolemization_stylesheet = "${STYLESHEET_HOME}/eprover-safe-skolemizations.xsl";
my $safe_skolemization_status = system ("xsltproc ${safe_skolemization_stylesheet} ${tptp_xml} > /dev/null 2>&1");
my $safe_skolemization_exit_code = $safe_skolemization_status >> 8;
if ($safe_skolemization_status != 0) {
    die error_message ('The given proof has at least one skolemization step that produces multiple skolem functions.');
}

# Clean the HTML
my $clean_tptp_xml = "${db}/${tptp_basename}.xml.clean";
my $clean_stylesheet = "${STYLESHEET_HOME}/clean-eprover.xsl";
my $clean_status = system ("xsltproc ${clean_stylesheet} ${tptp_xml} > ${clean_tptp_xml}");
my $clean_exit_code = $clean_status >> 8;

if ($clean_exit_code != 0) {
    die error_message ('Error: xsltproc did not exit cleanly when cleaning up ${tptp_xml}.');
}

# Make the required subdirectories

foreach my $dir (@subdirs) {
    mkdir "${db}/${dir}"
	or croak ('Error: unable to make the directory \'', $dir, '\' in the Mizar db directory (', $db, ').');
}

my %directory_for_extension = (
    'voc' => 'dict',
    'evl' => 'text',
    'wsx' => 'text',
    'dno' => 'prel',
    'dco' => 'prel',
    'the' => 'prel',
);

my @extensions_to_generate = ('voc', 'evl', 'dno', 'dco', 'wsx', 'the');

my $cwd = getcwd;
my $prel_subdir = "${db}/prel";
my $prel_subdir_full = "${cwd}/${prel_subdir}";

foreach my $extension (@extensions_to_generate) {
    my $subdir_name = $directory_for_extension{$extension};
    my $subdir = "${db}/${subdir_name}";
    my $stylesheet = "${STYLESHEET_HOME}/eprover2${extension}.xsl";
    my $output_file = "${subdir}/${tptp_short_name}.${extension}";
    my $xsltproc_parameters = "--stringparam article '$tptp_short_name' --stringparam prel-directory '${prel_subdir_full}'";
    if ($opt_nested) {
	$xsltproc_parameters .= " --stringparam shape 'nested' ";
    } else {
	$xsltproc_parameters .= " --stringparam shape 'flat' ";
    }
    my $xsltproc_status = system ("xsltproc ${xsltproc_parameters} $stylesheet ${clean_tptp_xml} > $output_file");
    my $xsltproc_error_message = $!;
    my $xsltproc_exit_code = $xsltproc_status >> 8;
    if ($xsltproc_exit_code != 0) {
	croak ('Error: xsltproc did not exit cleanly when generating the .', $extension, ' file for', "\n", "\n", '  ', $tptp_file, "\n", "\n", 'The exit code was ', $xsltproc_exit_code, '. The error message was:',  "\n", "\n", '  ', $xsltproc_error_message);
    }
}

my @skolem_extensions = ('the');

foreach my $extension (@skolem_extensions) {
    my $stylesheet = "${STYLESHEET_HOME}/eprover2${extension}.xsl";
    my $path = "${db}/prel/skolem.${extension}";
    my $xsltproc_status = system ("xsltproc --stringparam article '${tptp_short_name}' --stringparam prel-directory '${prel_subdir_full}' $stylesheet ${clean_tptp_xml} > $path");
    my $xsltproc_exit_code = $xsltproc_status >> 8;
    if ($xsltproc_exit_code != 0) {
	croak ('Error: xsltproc did not exit cleanly when generating skolem.', $extension, ' for', "\n", "\n", '  ', $tptp_file, "\n", "\n", 'The exit code was ', $xsltproc_exit_code);
    }
}

my $pp_stylesheet = "${STYLESHEET_HOME}/pp.xsl";
my $wsx_path = "${db}/text/${tptp_short_name}.wsx";
my $miz_path = "${db}/text/${tptp_short_name}.miz";
    my $xsltproc_status = system ("xsltproc $pp_stylesheet $wsx_path > $miz_path 2>/dev/null");
my $xsltproc_exit_code = $xsltproc_status >> 8;
if ($xsltproc_exit_code != 0) {
    croak ('Error: xsltproc did not exit cleanly when generating the .miz file for', "\n", "\n", '  ', $tptp_file, "\n", "\n", 'The exit code was ', $xsltproc_exit_code);
}

__END__

=pod

=head1 EPROOF2MIZ

eproof2miz - Transform an eprover proof into a Mizar article

=head1 SYNOPSIS

eproof2miz.pl [options] [tptp-file]

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

B<tptp2miz.pl> will transform the supplied TPTP file into a
corresponding Mizar article.

=cut
