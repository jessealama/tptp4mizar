#!/usr/bin/env perl

use strict;
use warnings;

require v5.10.0; # for the 'say' feature
use feature 'say';

use charnames qw(:full);
use Regexp::DefaultFlags;
use Readonly;
use Data::Dumper;
use Pod::Usage;
use Getopt::Long;
use File::Temp qw(tempdir tempfile);
use Cwd qw(getcwd);
use Carp qw(croak carp confess);
use IPC::Run qw(harness);
use IPC::Cmd qw(can_run);
use File::Copy qw(copy move);
use File::Basename qw(basename dirname);
use Term::ANSIColor qw(colored);
use List::MoreUtils qw(any);

use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Utils qw(apply_stylesheet
	     slurp
	     list_to_token_string
	     items_of_token_string);

# Strings
Readonly my $EMPTY_STRING => q{};
Readonly my $SP => q{ };
Readonly my $COLON => q{:};
Readonly my $FS => q{.};
Readonly my $LF => "\N{LF}";

# Mizar error codes
Readonly my $IRRTHS_ERR_CODE => 706;
Readonly my $IRRVOC_ERR_CODE => 709;

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
    'irrths',
    'irrvoc',
);
Readonly my @ENHANCERS => (@DANGEROUS_ENHANCERS, @SAFE_ENHANCERS);

# Colors
Readonly my $ERROR_COLOR => 'red';
Readonly my $WARNING_COLOR => 'yellow';

# Stylesheets
Readonly my $COMPRESS_STYLESHEET => "$RealBin/../xsl/mizar/compress.xsl";
Readonly my $PP_STYLESHEET => "$RealBin/../xsl/mizar/pp.xsl";

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

my $opt_man = 0;
my $opt_help = 0;
my $opt_debug = 0;

sub process_commandline {
    my $commandline_ok
	= GetOptions (
	    'help' => \$opt_help,
	    'man' => \$opt_man,
	    'debug' => \$opt_debug,
	);

    if (! $commandline_ok) {
	pod2usage (
	    -exitval => 2,
	);
    }

    if ($opt_help) {
	pod2usage(
	    -exitstatus => 0,
	    -verbose => 2,
	);
    }

    if ($opt_man) {
	pod2usage(
	    -exitstatus => 0,
	    -verbose => 2,
	);
    }

    if (scalar @ARGV != 1) {
	pod2usage (
	    -exitval => 2,
	);
    }

    my $article = $ARGV[0];
    my $article_dirname = dirname ($article);
    my $article_basename = basename ($article, '.miz');
    my $article_miz = "${article_dirname}/${article_basename}.miz";

    if (! is_readable_file ($article_miz)) {
	die error_message ('The given file', $SP, $article, $SP, 'does not exist or is unreadable.');
    }

    if (! all_enhancers_runnable ()) {
	die error_message 'Not all the Mizar text enhancers are runnable.';
    }

    return $article_miz;
}

sub sensible_err_file {
    my $article_err = shift;

    if (-e $article_err) {

	my @err_lines = slurp ($article_err);

	if ($opt_debug) {
	    warn 'Error lines:', "\N{LF}", join ("\N{LF}", @err_lines);
	}

	if (any { $_ =~ /\N{SPACE} 4 \z/ } @err_lines) {
	    return 0;
	} else {
	    return 1;
	}
    } else {
	return 1;
    }

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

    # First, accommodate and parse
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
	    if (sensible_err_file ($article_err)) {
		$compressible = 1;
		last;
	    } else {
		die error_message ('It appears that', $SP, $program, $SP, 'did not work correctly on', $SP, $article, $FS, 'Here is the .err file:', $LF, slurp ($article_err));
	    }
	}
    }

    return $compressible;

}

sub cmp_line_col {
    my $line_col_a = shift;
    my $line_col_b = shift;

    if ($line_col_a =~ /\A (\d+) [:] (\d+) /) {
	(my $line_a, my $col_a) = ($1, $2);
	if ($line_col_b =~ /\A (\d+) [:] (\d+) /) {
	    (my $line_b, my $col_b) = ($1, $2);
	    if ($line_a < $line_b) {
		return -1;
	    } elsif ($line_a == $line_b) {
		if ($col_a < $col_b) {
		    return -1;
		} elsif ($col_a == $col_b) {
		    return 0;
		} elsif ($col_a > $col_b) {
		    return 1;
		}
	    } elsif ($line_a > $line_b) {
		return 1;
	    }
	} else {
	    die 'Unable to parse line and column info from ', $line_col_b;
	}
    } else {
	die 'Unable to parse line and column info from ', $line_col_a;
    }

}

sub recommend_compressions {
    my $article = shift;

    my $article_dirname = dirname ($article);
    my $article_basename = basename ($article, '.miz');
    my $article_err = "${article_dirname}/${article_basename}.err";

    if (-e $article_err) {
	unlink $article_err; # ensure that we start from scratch
    }

    my %recommendations = ();

    foreach my $program (@ENHANCERS) {
	run_mizar_tool ($program, $article);
	if (! -e $article_err) {
	    die error_message ('It appears that', $SP, $program, $SP, 'did not work correctly on', $SP, $article, $SP, '(it did not generate an error file)');
	} elsif (! -r $article_err) {
	    die error_message ('It appears that', $SP, $program, $SP, 'did not work correctly on', $SP, $article, $SP, '(the error file is unreadable)');
	} elsif (-z $article_err) {
	    next;
	} else {
	    if (sensible_err_file ($article_err)) {
		my $err_contents = slurp ($article_err);
		my @err_lines = split ("\N{LF}", $err_contents);
		foreach my $err_line (@err_lines) {
		    if ($err_line =~ /\A (\d+) \N{SPACE} (\d+) \N{SPACE} (\d+) \z/) {
			(my $line, my $col, my $code) = ($1, $2, $3);
			$recommendations{"${line}:${col}"} = $code;
		    } else {
			die 'Error: unable to make sense of the .err line \'', $err_line, '\'.';
		    }
		}
	    } else {
		die error_message ('It appears that', $SP, $program, $SP, 'did not work correctly on', $SP, $article, $FS);
	    }
	}
    }

    my $recommendation = $EMPTY_STRING;

    my @recommendations = keys %recommendations;
    my @sorted_recommendations = sort { cmp_line_col ($a, $b) } @recommendations;

    @sorted_recommendations
	= map { $_ . ':' . $recommendations{$_}} @sorted_recommendations;

    # warn '@sorted_recommendations is', "\N{LF}", Dumper (@sorted_recommendations);

    # Ensure that nothing intervenes within an inacc block
    my %recommendations_to_keep = ();
    foreach my $i (0 .. scalar @sorted_recommendations - 1) {
	my $recommendation = $sorted_recommendations[$i];
	if ($recommendation =~ / [:] 610 \z/) {
	    if ($i < scalar @sorted_recommendations - 1) {
		my $next_recommendation = $sorted_recommendations[$i + 1];
		if ($next_recommendation =~ / [:] 611 \z/) {
		    $recommendations_to_keep{$recommendation} = 0;
		} else {
		    if ($opt_debug) {
			warn 'The 610 recommendation ', $recommendation, ' is not immediately followed by a closing 611 recommendation.  Ignoring it...';
		    }
		}
	    }
	} elsif ($recommendation =~ / [:] 611 \z/) {
	    if ($i > 0) {
		my $previous_recommendation = $sorted_recommendations[$i - 1];
		if ($previous_recommendation =~ / [:] 610 \z/) {
		    $recommendations_to_keep{$recommendation} = 0;
		} else {
		    if ($opt_debug) {
			warn 'The 611 recommendation ', $recommendation, ' is not immediately preceded by an opening 610 recommendation.  Ignoring it...';
		    }
		}
	    }
	} else {
	    $recommendations_to_keep{$recommendation} = 0;
	}
    }

    @sorted_recommendations
	= sort { cmp_line_col ($a, $b) } keys %recommendations_to_keep;

    return ',' . join (',', @sorted_recommendations) . ',';

}

sub errors_with_code {
    my $token_string = shift;
    my $error_code = shift;

    my @errors = ();

    my @items = items_of_token_string ($token_string);

    foreach my $item (@items) {
	if ($item =~ / (\d+) [:] (\d+) [:] (\d+) /) {
	    (my $line, my $col, my $code) = ($1, $2, $3);
	    if ($code eq $error_code) {
		push (@errors, "${line}:${col}");
	    }
	} else {
	    confess 'Unable to make sense of the item \'', $item, '\' appearing in the token string \'', $token_string, '\'.';
	}
    }

    if (wantarray) {
	return @errors;
    } else {
	return \@errors;
    }
}

sub apply_recommendations {
    my $article = shift;
    my $recommendation = shift;

    my $article_dirname = dirname ($article);
    my $article_basename = basename ($article, '.miz');
    my $article_wsx = "${article_dirname}/${article_basename}.wsx";
    my $article_evl
	= File::Spec->rel2abs ("${article_dirname}/${article_basename}.evl");
    my $article_wsx_temp = "${article_dirname}/${article_basename}.wsx1";
    my $article_miz = "${article_dirname}/${article_basename}.miz";

    apply_stylesheet ($COMPRESS_STYLESHEET,
		      $article_wsx,
		      $article_wsx,
		      {
			  'recommendations' => $recommendation,
		      }
		  );

    # Recommendations from irrths and irrvoc won't be handled by the
    # WSX stylesheet.  We need to treat them separately.
    my @irrths_errors = errors_with_code ($recommendation, "${IRRTHS_ERR_CODE}");
    my @irrvoc_errors = errors_with_code ($recommendation, "${IRRVOC_ERR_CODE}");

    # warn 'irrths and irrvoc errors', $LF, Dumper (@irrths_errors), Dumper (@irrvoc_errors);

    my $delete_evl_identifiers_stylesheet = "$RealBin/../xsl/mizar/delete-evl-identifiers.xsl";
    apply_stylesheet ($delete_evl_identifiers_stylesheet,
		      $article_evl,
		      $article_evl,
		      {
			  'to-delete' => list_to_token_string (@irrths_errors),
		      }
		  );

    apply_stylesheet ($delete_evl_identifiers_stylesheet,
		      $article_evl,
		      $article_evl,
		      {
			  'to-delete' => list_to_token_string (@irrvoc_errors),
		      }
		  );

    apply_stylesheet ($PP_STYLESHEET,
		      $article_wsx,
		      $article_miz,
		      {
			  'indenting' => '1',
			  'evl' => $article_evl,
		      }
		  );

    return 1;

}

my $article = process_commandline ();
my $article_dirname = dirname ($article);
my $article_basename = basename ($article, '.miz');
my $article_miz = "${article_dirname}/${article_basename}.miz";

my $fresh_article = "${article_dirname}/compress.miz";
my $fresh_article_wsx = "${article_dirname}/compress.wsx";
my $fresh_article_old = "${article_dirname}/compress.miz.old";
my $fresh_article_wsx_old = "${article_dirname}/compress.wsx.old";

copy ($article, $fresh_article)
    or die 'Failed to make a copy of ', $article, ': ', $!;

run_mizar_tool ('accom', $fresh_article);
run_mizar_tool ('wsmparser', $fresh_article);

my %applied_recommendations = ();

my $compression_recommendations = recommend_compressions ($fresh_article);

if ($opt_debug) {
    say 'Recommendations: ', $compression_recommendations;
}

while ($compression_recommendations ne ',,'
	   && ( ! defined $applied_recommendations{$compression_recommendations}
		    || $applied_recommendations{$compression_recommendations} < 2)) {
#                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
#
# permit looking at a recommentation 2 times, in case we are able to
# perform some compresisons that don't trigger errors (and hence may
# lead to identical recommendations coming up more than once)

    # Save our work
    if (-e $fresh_article_wsx) {
	copy ($fresh_article_wsx, $fresh_article_wsx_old);
    }
    copy ($fresh_article, $fresh_article_old);

    apply_recommendations ($fresh_article, $compression_recommendations);
    if (defined $applied_recommendations{$compression_recommendations}) {
	my $old_val = $applied_recommendations{$compression_recommendations};
	$applied_recommendations{$compression_recommendations} = $old_val + 1;
    } else {
	$applied_recommendations{$compression_recommendations} = 0;
    }

    $compression_recommendations = recommend_compressions ($fresh_article);

    if ($opt_debug) {
	say 'Recommendations: ', $compression_recommendations;
    }

    run_mizar_tool ('wsmparser', $fresh_article);
}

# Clean up: remove all the 'compress.*' files, save a copy of the
# supplied article, rename compress.miz to the name of the given article
my $article_miz_copy = "${article_dirname}/${article_basename}.miz.orig";

copy ($article_miz, $article_miz_copy)
    or die error_message ('Unable to save a copy of', $SP, $article_miz, $SP, 'to', $SP, $article_miz_copy, ':', $SP, $!);

move ($fresh_article, $article_miz)
    or die error_message ('Unable to rename the compressed article', $SP, $fresh_article, $SP, 'to \'',  $article_miz, '\':', $SP, $!);

run_mizar_tool ('wsmparser', $article_miz);

my @compressed_files = glob "${article_dirname}/compress.*";

foreach my $file (@compressed_files) {
    unlink $file
	or die error_message ('Unable to delete', $SP, $file, ':', $SP, $!);
}

__END__

=pod

=head1 NAME mcompress

Compress Mizar texts by repeatedly using proof enhancers

=head1 SYNOPSIS

mcompress [options] MIZAR-ARTICLE

=head1 DESCRIPTION

=cut
