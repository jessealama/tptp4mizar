package TSTPDerivation;

use Moose;
use Pod::Find qw(pod_where);
use Pod::Usage;
use Data::Dumper;
use Carp qw(croak carp);
use File::Temp qw(tempfile);
use Readonly;
use Regexp::DefaultFlags;
use charnames qw(:full);
use List::MoreUtils qw(none);

use feature 'say';

Readonly my $LF => "\N{LF}";

has 'background_theory' => (
    is => 'ro',
    reader => 'get_background_theory',
);

has 'raw_text' => (
    isa => 'Str',
    is => 'ro',
    reader => 'get_raw_text',
);

1;
__END__

=pod

=head1 NAME

Derivation

=head1 DESCRIPTION

This is the base class of all TSTP-style derivations.


=head1 DEPENDENCIES

=over 8

=item L<Moose|http://search.cpan.org/~doy/Moose-2.0403/lib/Moose.pm>

=back

=cut
