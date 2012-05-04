package TPTPProblem;

require v5.10.0; # for the 'say' feature
use feature 'say';

use Moose;
use Pod::Find qw(pod_where);
use Pod::Usage;
use Data::Dumper;
use Carp qw(croak carp confess);
use File::Temp qw(tempfile);
use Readonly;
use Regexp::DefaultFlags;
use charnames qw(:full);
use List::MoreUtils qw(none);
use IPC::Run qw(harness);
use FindBin qw($RealBin);

use base qw(Exporter);
our @EXPORT_OK = qw(is_valid_tptp_file);

# Our stuff
use Utils qw(error_message);

# Strings
Readonly my $LF => "\N{LF}";
Readonly my $EMPTY_STRING => q{};
Readonly my $TPTP4X => 'tptp4X';

# Directories
Readonly my $STYLESHEET_HOME => "$RealBin/../xsl";
Readonly my $TPTP_STYLESHEET_HOME => "${STYLESHEET_HOME}/tptp";
Readonly my $MIZAR_STYLESHEET_HOME => "${STYLESHEET_HOME}/mizar";

has 'raw_text' => (
    isa => 'Str',
    is => 'ro',
    reader => 'get_raw_text',
);

has 'path' => (
    isa => 'Str',
    is => 'ro',
    reader => 'get_path',
);

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

my @extensions_to_generate = ('voc', 'evl', 'dno', 'dco', 'wsx');

my %directory_for_extension = (
    'voc' => 'dict',
    'evl' => 'text',
    'wsx' => 'text',
    'dno' => 'prel',
    'dco' => 'prel',
    'the' => 'prel',
);

sub to_miz {
    my $self = shift;
    my $directory = shift;
    my $options_ref = shift;

    my %options = defined $options_ref ? %{$options_ref} : ();

    my $path = $self->get_path ();

    my $directory_full = File::Spec->rel2abs ($directory);

    foreach my $subdir_name ('dict', 'prel', 'text') {
	my $subdir = "${directory_full}/${subdir_name}";
	mkdir $subdir
	    or confess error_message ('Unable to make the \'', $subdir_name, '\' subdirectory of ', $directory_full, '.');
    }

    my $prel_subdir_full = "${directory_full}/prel";

    foreach my $extension (@extensions_to_generate) {
	my $subdir_name = $directory_for_extension{$extension};
	my $subdir = "${directory}/${subdir_name}";

	my @xsltproc_call = ('xsltproc',
			     '--stringparam', 'article', 'article',
			     '--stringparam', 'prel-directory', $prel_subdir_full);

	if (defined $options{'shape'}) {
	    my $shape = $options{'shape'};
	    if ($shape eq 'nested') {
		push (@xsltproc_call, '--stringparam', 'shape', 'nested');
	    } elsif ($shape eq 'flat') {
		push (@xsltproc_call, '--stringparam', 'shape', 'flat');
	    } else {
		confess error_message ('Unknown proof shape \'', $shape, '\'.');
	    }
	} else {
	    push (@xsltproc_call, '--stringparam', 'shape', 'flat');
	}

	push (@xsltproc_call, "${TPTP_STYLESHEET_HOME}/tptp2${extension}.xsl");
	push (@xsltproc_call, $path);

	my $xsltproc_err = $EMPTY_STRING;
	my $xsltproc_harness = harness (\@xsltproc_call,
					'>', "${subdir}/article.${extension}",
					'2>', \$xsltproc_err);

	$xsltproc_harness->start ();
	$xsltproc_harness->finish ();

	my $xsltproc_exit_code = ($xsltproc_harness->results)[0];

	if ($xsltproc_exit_code != 0) {
	    confess error_message ('xsltproc did not exit cleanly when generating the .', $extension, ' file for', "\n", "\n", '  ', $path, "\n", "\n", 'The exit code was ', $xsltproc_exit_code, '. The error message was:',  "\n", "\n", '  ', $xsltproc_err);
	}
    }

    my $pp_stylesheet = "${MIZAR_STYLESHEET_HOME}/pp.xsl";
    my $wsx_path = "${directory}/text/article.wsx";
    my $miz_path = "${directory}/text/article.miz";
    my $xsltproc_status = system ("xsltproc $pp_stylesheet $wsx_path > $miz_path");
    my $xsltproc_exit_code = $xsltproc_status >> 8;
    if ($xsltproc_exit_code != 0) {
	croak ('Error: xsltproc did not exit cleanly when generating the .miz file for', "\n", "\n", '  ', $path, "\n", "\n", 'The exit code was ', $xsltproc_exit_code);
    }

    return;
}

1;
__END__

=pod

=head1 TPTPProblem

Derivation

=head1 DESCRIPTION

A utility class for TPTP problems.

=head1 DEPENDENCIES

=over 8

=item L<Moose|http://search.cpan.org/~doy/Moose-2.0403/lib/Moose.pm>

=back

=cut
