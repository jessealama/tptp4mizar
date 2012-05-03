package Strings;

use charnames qw(:full);
use base qw(Exporter);
our @EXPORT_OK = qw($EMPTY_STRING
		    $SP
		    $COLON
		    $LF);
use Readonly;

# Strings
Readonly my $EMPTY_STRING => q{};
Readonly my $SP => q{ };
Readonly my $COLON => q{:};
Readonly my $LF => "\N{LF}";

1;
__END__