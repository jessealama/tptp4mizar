#!/usr/bin/env perl

use strict;
use warnings;

require v5.10.0; # for the 'say' feature
use feature 'say';

use charnames qw(:full);
use Regexp::DefaultFlags;
use Readonly;
use Pod::Usage;
use Getopt::Long;
use File::Temp qw(tempdir tempfile);
use Cwd qw(getcwd);
use Carp qw(croak carp);
use IPC::Run qw(harness);
use IPC::Cmd qw(can_run);
use File::Copy qw(copy);
use File::Basename qw(basename dirname);
use Term::ANSIColor qw(colored);
use FindBin qw($RealBin);

# Strings
Readonly my $EMPTY_STRING => q{};
Readonly my $SP => q{ };
Readonly my $COLON => q{:};
Readonly my $FS => q{.};

# Programs
Readonly my @CORE_PROGRAMS => (
    'accom',
    'wsmparser',
);
Readonly my @DANGEROUS_ENHANCERS => (
    'relinfer',
    'relprem',
);
Readonly my @SAFE_ENHANCERS => (
    'trivdemo',
    'chklab',
    'inacc',
);
Readonly my @ENHANCERS => (@DANGEROUS_ENHANCERS, @SAFE_ENHANCERS);

# Colors
Readonly my $ERROR_COLOR => 'red';
Readonly my $WARNING_COLOR => 'yellow';

sub is_readable_file {
    my $file = shift;
    return (-e $file && ! -d $file && -r $file);
}

sub all_enhancers_runnable {
    my @unrunnable = unrunnable_enhaners ();
    return (scalar @unrunnable == 0);
}

sub unrunnable_enhaners {
    my @cannot_run = ();
    foreach my $program (@ENHANCERS) {
	if (! can_run ($program)) {
	    warn 'cannot run', $SP, $program;
	    push (@cannot_run, $program);
	}
    }
    return @cannot_run;
}

sub error_message {
    return message_with_colored_prefix ('Error', $ERROR_COLOR, @_);
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

sub process_commandline {
    my $commandline_ok
	= GetOptions ();

    if (! $commandline_ok) {
	pod2usage (
	    -exitval => 2,
	);
    }

    if (scalar @ARGV != 1) {
	pod2usage (
	    -exitval => 2,
	);
    }

    my $article = $ARGV[0];

    if (! is_readable_file ($article)) {
	die error_message ('The given file', $SP, $article, $SP, 'does not exist or is unreadable.');
    }

    if (! all_enhancers_runnable ()) {
	die error_message 'Not all the Mizar text enhancers are runnable.';
    }

    return $article;
}

sub slurp {
    my $path_or_fh = shift;

    open( my $fh, '<', $path_or_fh )
        or die error_message ('Unable to open the file (or filehandle) ', $path_or_fh, $FS);

    my $contents;
    { local $/; $contents = <$fh>; }

    close $fh
        or die error_message ('Unable to close the file (or filehandle) ', $path_or_fh,$FS);

    return $contents;
}

sub sensible_err_file {
    my $article = shift;

    my $article_basename = basename ($article, '.miz');
    my $article_err = "${article_basename}.err";
}

sub run_mizar_tool {
    my $tool = shift;
    my $article = shift;

    if (! can_run ($tool)) {
	die error_message ($tool, $SP, 'is not executable.');
    }

    my $tool_out = $EMPTY_STRING;
    my $tool_err = $EMPTY_STRING;
    my @tool_call = ($tool, '-q', '-l', $article);
    my $tool_harness = harness (\@tool_call,
				'>', \$tool_out,
				'2>', \$tool_err);

    $tool_harness->start ();
    $tool_harness->finish ();

}

sub is_compressible {
    my $article = shift;

    my $article_dirname = dirname ($article);
    my $article_basename = basename ($article, '.miz');
    my $article_err = "${article_dirname}/${article_basename}.err";

    my $compressible = 0;

    # First, accommodate
    my $accom_result = system ("accom -q -s -l ${article} > /dev/null 2>/dev/null");
    my $accom_exit_code = $accom_result >> 8;

    if ($accom_exit_code != 0) {
	die error_message ('accom did not exit cleanly working with', $SP, $article, $FS);
    }

    foreach my $program (@ENHANCERS) {
	run_mizar_tool ($program, $article);
	if (! -e $article_err) {
	    die error_message ('It appears that', $SP, $program, $SP, 'did not work correctly on', $SP, $article, $SP, '(it did not generate an error file)');
	} elsif (! -r $article_err) {
	    die error_message ('It appears that', $SP, $program, $SP, 'did not work correctly on', $SP, $article, $SP, '(the error file is unreadable)');
	} elsif (-z $article_err) {
	    next;
	} else {
	    if (sensible_err_file ($article)) {
		$compressible = 1;
	    } else {
		die error_message ('It appears that', $SP, $program, $SP, 'did not work correctly on', $SP, $article, $FS);
	    }
	}
    }

    return $compressible;

}

my $article = process_commandline ();

if (is_compressible ($article)) {
    say 'Compressible';
} else {
    say 'Not compressible.';
}

exit 0;

__END__

=pod

=head1 NAME mcompress

Compress Mizar texts by repeatedly using proof enhancers

=head1 SYNOPSIS

mcompress [options] MIZAR-ARTICLE

=head1 DESCRIPTION

=cut
