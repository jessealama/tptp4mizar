package IvyDerivation;

use Moose;
use Carp qw(carp confess croak);
use Pod::Find qw(pod_where);
use Pod::Usage;
use Regexp::DefaultFlags;
use charnames qw(:full);
use English qw(-no_match_vars);
use FindBin qw($RealBin);
use Readonly;
use File::Spec;
use File::Temp qw(tempfile);
use IPC::Run qw(harness);

use Utils qw(error_message apply_stylesheet);

extends 'TSTPDerivation';

Readonly my $EMPTY_STRING => q{};
Readonly my $STYLESHEET_HOME => "$RealBin/../xsl";
Readonly my $IVY_STYLESHEET_HOME => "${STYLESHEET_HOME}/ivy";
Readonly my $MIZAR_STYLESHEET_HOME => "${STYLESHEET_HOME}/mizar";

my %directory_for_extension = (
    'voc' => 'dict',
    'evl' => 'text',
    'wsx' => 'text',
    'dno' => 'prel',
    'dco' => 'prel',
    'the' => 'prel',
);

my @extensions_to_generate = ('voc', 'evl', 'dno', 'dco', 'the', 'wsx');

sub to_miz {
    my $self = shift;
    my $directory = shift;
    my $article_name = shift;
    my $options_ref = shift;

    my %options = defined $options_ref ? %{$options_ref} : ();

    my $path = $self->get_path ();

    my $directory_full = File::Spec->rel2abs ($directory);

    foreach my $subdir_name ('dict', 'prel', 'text') {
	my $subdir = "${directory_full}/${subdir_name}";
	if (! -d $subdir) {
	    mkdir $subdir
		or confess error_message ('Unable to make the \'', $subdir_name, '\' subdirectory of ', $directory_full, '.');
	}
    }

    my $prel_subdir_full = "${directory_full}/prel";

    foreach my $extension (@extensions_to_generate) {
	my $subdir_name = $directory_for_extension{$extension};
	my $subdir = "${directory}/${subdir_name}";
	my $shape = defined $options{'shape'} ? $options{'shape'} : 'flat';
	my $stylesheet_for_extension = "${IVY_STYLESHEET_HOME}/ivy2${extension}.xsl";
	my $file_to_generate = "${subdir}/${article_name}.${extension}";

	apply_stylesheet ($stylesheet_for_extension,
			  $path,
			  $file_to_generate,
			  {
			      'article' => $article_name,
			      'prel-directory' => $prel_subdir_full,
			      'shape' => $shape,
			  });

    }

    my $pp_stylesheet = "${MIZAR_STYLESHEET_HOME}/pp.xsl";
    my $wsx_path = "${directory}/text/${article_name}.wsx";
    my $miz_path = "${directory}/text/${article_name}.miz";
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

=head1 NAME

IvyDerivation

=head1 DESCRIPTION

IvyDerivation is a subclass of Derivation that extracts used
premises from proof objects emitted by the Ivy proof checker.

=head1 SEE ALSO

=over 8

=item L<"Ivy: A preprocessor and proof checker for first-order logic", by William McCune  and Olga Shumsky|http://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.45.4430>

=back

=back

=cut
