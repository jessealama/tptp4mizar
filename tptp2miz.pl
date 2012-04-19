#!/usr/bin/env perl

use warnings;
use strict;

require v5.10.0;		# for the 'say' feature
use feature 'say';

use File::Copy qw(copy);
use File::Basename qw(basename dirname);
use Getopt::Long;
use Pod::Usage;
use Carp qw(croak carp);
use IPC::Run qw(harness);
use IPC::Cmd qw(can_run);
use Readonly;
use charnames qw(:full);
use Regexp::DefaultFlags;
use Term::ANSIColor qw(colored);

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

my $options_ok = GetOptions (
    "db=s"     => \$db,
    "verbose"  => \$verbose,
    'help' => \$help,
    'man' => \$man,
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

if (length $tptp_sans_extension == 0) {
    error_message ('After stipping the extension of the supplied TPTP theory file, we are left with just the empty string, which is an unacceptable name for a Mizar article.');
    exit 1;
}

my $tptp_short_name = substr $tptp_basename,0,8;

if (length $tptp_sans_extension > 8) {
    warning_message ('The length of the basename of the supplied file, even when its extension is stripped, exceeds 8 characters.', "\n", 'Since Mizar articles are requires to have names at most 8 characters long, we have truncated the name to \'', $tptp_short_name, '\'.', "\n");
}

if ($tptp_short_name !~ / \A [a-zA-Z0-9_]{1,8} \z /x) {
    error_message ('The name that we will use for the Mizar article, \'', $tptp_short_name, '\', is unacceptabl as the name of a Mizar article.', "\n", 'Valid names for Mizar articles are alphanumeric characters and the underscore \'_\'.');
    exit 1;
}

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

# Load all symbols
my $GetSymbols_result = `GetSymbols -all $tptp_file 2>/dev/null`;
my $GetSymbols_exit_code = $? >> 8;
if ($GetSymbols_exit_code != 0) {
    croak ('Error: GetSymbols did not exit cleanly when extracting the symbols from ', $tptp_file, '.');
}
chomp $GetSymbols_result;
if ($GetSymbols_result =~ /\A symbols \( all, \[ (.*) \], \[ (.*) \] \) [.] \z/mx) {
    (my $GetSymbols_functions, my $GetSymbols_predicates) = ($1, $2);
    my @function_infos = split (/[,]/x, $GetSymbols_functions);
    my @predicate_infos = split (/[,]/x, $GetSymbols_predicates);

    # Confirm that no function occurs with two different arities
    my %function_arity_table = ();
    foreach my $function_info (@function_infos) {
	if ($function_info =~ /\A (.+) \/ ([0-9]+) \/ [1-9][0-9]* \z/mx) {
	    (my $name, my $arity) = ($1, $2);
	    if (defined $function_arity_table{$name}) {
		my $earlier_arity = $function_arity_table{$name};
		if ($arity != $earlier_arity) {
		    croak ('Error: the function named \'', $name, '\' occurs at least once with arity ', $earlier_arity, ' and once with arity ', $arity, '.');
		}
	    } else {
		$function_arity_table{$name} = $arity;
	    }
	} else {
	    croak ('Error: unable to make sense of the function symbol info string \'', $function_info, '\' coming from the GetSymbols utility.');
	}
    }

    if ($verbose) {
	print 'Sanity Check: In the the given TPTP file, no function symbol occurs with different arities.', "\n";
    }

    # Confirm that no predicate occurs with two different arities
    my %predicate_arity_table = ();
    foreach my $predicate_info (@predicate_infos) {
	if ($predicate_info =~ /\A (.+) \/ ([0-9]+) \/ [1-9][0-9]* \z/mx ) {
	    (my $name, my $arity) = ($1, $2);
	    if (defined $predicate_arity_table{$name}) {
		my $earlier_arity = $predicate_arity_table{$name};
		if ($arity != $earlier_arity) {
		    croak ('Error: the predicate named \'', $name, '\' occurs at least once with arity ', $earlier_arity, ' and once with arity ', $arity, '.');
		}
	    } else {
		$predicate_arity_table{$name} = $arity;
	    }
	} else {
	    croak ('Error: unable to make sense of the predicate symbol info string \'', $predicate_info, '\' coming from the GetSymbols utility.');
	}
    }

    if ($verbose) {
	print 'Sanity Check: In the the given TPTP file, no predicate symbol occurs with different arities.', "\n";
    }

    # Confirm that no function occurs also as a predicate
    foreach my $symbol (keys %function_arity_table) {
	if (defined $predicate_arity_table{$symbol}) {
	    croak ('Error: the symbol \'', $symbol, '\' occurs both as a function and as a predicate in the given TPTP theory.');
	}
    }

    foreach my $symbol (keys %predicate_arity_table) {
	if (defined $function_arity_table{$symbol}) {
	    croak ('Error: the symbol \'', $symbol, '\' occurs both as a function and as a predicate in the given TPTP theory.');
	}
    }

    if ($verbose) {
	print 'Sanity Check: In the given TPTP file, no symbol occurs both as a function and as a predicate.', "\n";
    }

} else {
    croak ('Error: Unable to make sense of the GetSymbols output', "\n", "\n", '  ', $GetSymbols_result);
}

if (defined $db) {
    if (-e $db) {
	croak ('Error: the specified directory', "\n", "\n", '  ', $db, "\n", "\n", 'in which we are to save our work already exists.', "\n", 'Please use a different name');
    } else {
	mkdir $db
	    or croak ('Error: unable to make a directory at ', $db, '.');
    }
} else {
    if (-e $tptp_short_name) {
	croak ('Error: we are to save our work in the directory \'', $tptp_short_name, '\' inferred from the name of the supplied TPTP theory.', "\n", 'But there is already a file or directory by that name in the current working directory.', "\n", 'Use the --db option to specify a destination, or move the current file or directory out of the way.');
    }
    mkdir $tptp_short_name
	or croak ('Error: unable to make the directory \'', $tptp_short_name, '\' in the current working directory.');
    $db = $tptp_short_name;
}


######################################################################
## Creating the environment and the text
######################################################################

my $tptp_dirname = dirname ($tptp_file);

my @subdirs = ('text', 'prel', 'dict');

my $stylesheet_home = '/Users/alama/sources/mizar/xsl4mizar/tptp2miz';
my $tptp2voc_stylesheet = "${stylesheet_home}/tptp2voc.xsl";
my $tptp2miz_stylesheet = "${stylesheet_home}/tptp2miz.xsl";
my @extensions = ('dco', 'dno', 'voc', 'miz');
my @stylesheets = ('tptp2dco.xsl', 'tptp2dno.xsl', 'tptp2voc.xsl');
foreach my $stylesheet (@stylesheets) {
    my $stylesheet_path = "${stylesheet_home}/${stylesheet}";
    if (! -e $stylesheet_path) {
	croak ('Error: the required stylsheet ', $stylesheet, ' could not be found in the directory', "\n", "\n", '  ', $stylesheet_home, "\n", "\n", 'where we expect to find it.');
    }
    if (! -r $stylesheet_path) {
	croak ('Error: the required stylsheet ', $stylesheet, ' under', "\n", "\n", '  ', $stylesheet_home, "\n", "\n", 'is not readable.');
    }
}

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

# Make the required subdirectories

foreach my $dir (@subdirs) {
    mkdir "${db}/${dir}"
	or croak ('Error: unable to make the directory \'', $dir, '\' in the Mizar db directory (', $db, ').');
}

# Make the vocabulary
my $voc_file = "${db}/dict/${tptp_short_name}.voc";
my $tptp2voc_xsltproc_status = system ("xsltproc $tptp2voc_stylesheet $tptp_xml > $voc_file");
my $tptp2voc_xsltproc_exit_code = $tptp2voc_xsltproc_status >> 8;
if ($tptp2voc_xsltproc_exit_code != 0) {
    croak ('Error: xsltproc did not exit cleanly when making the vocabulary (.voc) file for', "\n", "\n", '  ', $tptp_file);
}

# Make the environment
foreach my $extension ('dno', 'dco') {
    my $stylesheet = "${stylesheet_home}/tptp2${extension}.xsl";
    if (! -e $stylesheet) {
	croak ('Error: the required stylesheet for generating the .', $extension, ' file does not exist at the expected location (', $stylesheet, ').');
    }
    my $output_file = "${db}/prel/${tptp_short_name}.${extension}";
    my $xsltproc_status = system ("xsltproc --stringparam article '$tptp_short_name' $stylesheet $tptp_xml > $output_file 2>/dev/null");
    my $xsltproc_exit_code = $xsltproc_status >> 8;
    if ($xsltproc_exit_code != 0) {
	croak ('Error: xsltproc did not exit cleanly when generating the .', $extension, ' file for', "\n", "\n", '  ', $tptp_file, "\n", "\n", 'The exit code was ', $xsltproc_exit_code);
    }
}

# Make the .miz
my $miz_file = "${db}/text/${tptp_short_name}.miz";
my $xsltproc_status = system ("xsltproc --stringparam article '$tptp_short_name' $tptp2miz_stylesheet $tptp_xml > $miz_file 2>/dev/null");
my $xsltproc_exit_code = $xsltproc_status >> 8;
if ($xsltproc_exit_code != 0) {
    croak ('Error: xsltproc did not exit cleanly when generating the .miz file for', "\n", "\n", '  ', $tptp_file, "\n", "\n", 'The exit code was ', $xsltproc_exit_code);
}

__END__

=pod

=head1 TPTP2MIZ

tptp2miz.pl - Transform a TPTP file into a Mizar article

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

By default, results will be saved in a directory whose name is derived
from the name of the supplied Mizar article (stripping the '.miz'
extension, if present).  This option permits saving work to some other
directory.  It is an error if the supplied directory already exists.

=back

=head1 DESCRIPTION

B<tptp2miz.pl> will transform the supplied TPTP file into a
corresponding Mizar article.

=cut
