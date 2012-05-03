package Colors;

use Exporter;
our @EXPORT_OK = qw($ERROR_COLOR $WARNING_COLOR);
use Readonly;

# Colors
Readonly my $ERROR_COLOR => 'red';
Readonly my $WARNING_COLOR => 'yellow';

1;
__END__
