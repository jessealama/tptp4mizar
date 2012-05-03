package VampireDerivation;

use Moose;
use Regexp::DefaultFlags;
use charnames qw(:full);
use English qw(-no_match_vars);

extends 'TSTPDerivation';

sub BUILD {
    my $self = shift;
    my $raw_text = $self->get_raw_text ();

}

1;
__END__

=pod

=head1 NAME

VampireDerivation

=head1 SEE ALSO

=over 8

=item L<The Vampire theorem prover|http://www.vprover.org/>

=back

=cut
