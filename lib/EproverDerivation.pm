package EproverDerivation;

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

use Utils qw(error_message
	     apply_stylesheet);

extends 'TSTPDerivation';

Readonly my $EMPTY_STRING => q{};
Readonly my $STYLESHEET_HOME => "$RealBin/../xsl";
Readonly my $EPROVER_STYLESHEET_HOME => "${STYLESHEET_HOME}/eprover";
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
    my $source_article_name = shift;
    my $source_tptp = shift;
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

	my %parameters =
	    (
		'article' => $article_name,
		'prel-directory' => $prel_subdir_full,
		# 'no-skolems' => '1',
		# 'skolem-prefix' => 'skolem',
		# 'skolem-dco' => "${prel_subdir_full}/skolem.dco",
		'background-article-name' => defined $source_article_name ?
		    $source_article_name
			: $EMPTY_STRING,
		'background-tptp-xml' => defined $source_tptp ?
		    $source_tptp
			: $EMPTY_STRING,
	    );

	if (defined $options{'shape'}) {
	    my $shape = $options{'shape'};
	    if ($shape eq 'nested') {
		$parameters{'shape'} = 'nested';
	    } elsif ($shape eq 'flat') {
		$parameters{'shape'} = 'flat';
	    } else {
		confess error_message ('Unknown proof shape \'', $shape, '\'.');
	    }
	} else {
	    $parameters{'shape'} = 'flat';
	}

	my $stylesheet = "${EPROVER_STYLESHEET_HOME}/eprover2${extension}.xsl";
	my $result = ($subdir_name eq 'prel' ?
			  "${subdir}/${article_name}e.${extension}"
			      : "${subdir}/${article_name}.${extension}");
	apply_stylesheet ($stylesheet,
			  $path,
			  $result,
			  \%parameters);

    }

    my $pp_stylesheet = "${MIZAR_STYLESHEET_HOME}/pp.xsl";
    my $evl_path = "${directory}/text/${article_name}.evl";
    my $wsx_path = "${directory}/text/${article_name}.wsx";
    my $miz_path = "${directory}/text/${article_name}.miz";

    return apply_stylesheet ($pp_stylesheet,
			     $wsx_path,
			     $miz_path,
			     {
				 'evl' => $evl_path,
			     }
			 );

}

1;
__END__

=pod

=head1 NAME

EproverDerivation

=head1 DESCRIPTION

EproverDerivation is a subclass of Derivation that extracts used
premises from proofs output by the E theorem prover.

=head1 SEE ALSO

=over 8

=item L<The E theorem prover|http://www.eprover.org/>

=back

=cut
