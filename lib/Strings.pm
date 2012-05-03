package Strings;

use Exporter;
our @EXPORT_OK = qw($EMPTY_STRING
		    $SP
		    $COLON);
use Readonly;

# Strings
Readonly my $EMPTY_STRING => q{};
Readonly my $SP => q{ };
Readonly my $COLON => q{:};

1;
__END__
