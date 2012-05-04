package TPTPProblem;

require v5.10.0; # for the 'say' feature
use feature 'say';

use base qw(Exporter);
our @EXPORT_OK = qw(is_valid_tptp_file);

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

# Our stuff
use Utils qw(error_message);

Readonly my $LF => "\N{LF}";
Readonly my $EMPTY_STRING => q{};
Readonly my $TPTP4X => 'tptp4X';

has 'raw_text' => (
    isa => 'Str',
    is => 'ro',
    reader => 'get_raw_text',
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

sub to_miz {
    confess error_message ('We do not yet support transforming arbitrary TPTP problems to Mizar texts.  Sorry!', $LF, 'Please complain loudly to the maintainers.');
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
