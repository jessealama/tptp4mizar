package Utils;

use strict;
use warnings;

use Carp qw(carp confess croak);
use Regexp::DefaultFlags;
use Term::ANSIColor qw(colored);
use Readonly;
use Data::Dumper;
use charnames qw(:full);
use IPC::Run qw(harness);
use IPC::Cmd qw(can_run);
use List::MoreUtils qw(first_index);
use XML::LibXML;
use XML::LibXSLT;
use FindBin qw($RealBin);

# Strings
Readonly my $EMPTY_STRING => q{};
Readonly my $SP => q{ };
Readonly my $COLON => q{:};
Readonly my $LF => "\N{LF}";

# Colors
Readonly my $ERROR_COLOR => 'red';
Readonly my $WARNING_COLOR => 'yellow';

# Stylesheets
Readonly my $STYLESHEET_HOME => "$RealBin/../xsl";
Readonly my $TSTP_STYLESHEET_HOME => "${STYLESHEET_HOME}/tstp";
Readonly my $SORT_TSTP_STYLESHEET => "${TSTP_STYLESHEET_HOME}/sort-tstp.xsl";
Readonly my $DEPENDENCIES_STYLESHEET => "${TSTP_STYLESHEET_HOME}/tstp-dependencies.xsl";
Readonly my $NORMALIZE_STEPS_STYLESHEET => "${TSTP_STYLESHEET_HOME}/normalize-step-names.xsl";

use base qw(Exporter);
our @EXPORT_OK = qw(error_message
		    warning_message
		    strip_extension
		    is_readable_file
		    is_valid_xml_file
		    slurp
		    run_mizar_tool
		    normalize_variables
		    tptp_xmlize
		    tptp_fofify
		    apply_stylesheet
		    run_harness
		    is_file
		    sort_tstp_solution
		    normalize_tstp_steps
		    list_to_token_string
		    items_of_token_string);

sub error_message {
    return message_with_colored_prefix ('Error', $ERROR_COLOR, @_);
}

sub warning_message {
    return message_with_colored_prefix ('Warning', $WARNING_COLOR, @_);
}

sub is_readable_file {
    my $file = shift;
    return (-e $file && ! -d $file && -r $file);
}

Readonly my $RECURSION_DEPTH => 3000;

XML::LibXSLT->max_depth ($RECURSION_DEPTH);

my %parsed_stylesheet_table = ();

sub apply_stylesheet {

    my ($stylesheet, $document, $result_path, $parameters_ref) = @_;

    if (! defined $stylesheet) {
	croak ('Error: please supply a stylesheet.');
    }

    if (! defined $document) {
	croak ('Error: please supply a document.');
    }

    my %parameters = XML::LibXSLT::xpath_to_string
	(defined $parameters_ref ? %{$parameters_ref} : () );

    my $parsed_stylesheet = $parsed_stylesheet_table{$stylesheet};
    if (! defined $parsed_stylesheet) {
	my $xslt = XML::LibXSLT->new ();
	my $style_doc = XML::LibXML->load_xml (location => $stylesheet);
	$parsed_stylesheet = eval { $xslt->parse_stylesheet ($style_doc) };

	if (! defined $parsed_stylesheet) {
	    croak error_message ('The stylesheet at', $SP, $stylesheet, $SP, 'could not be parsed.');
	}

	$parsed_stylesheet_table{$stylesheet} = $parsed_stylesheet;
    }

    my $results = undef;
    my $xslt_err = undef;

    if ($document =~ /\N{LF}/m) { # looks like a string
	my $doc = XML::LibXML->load_xml (string => $document);
	$results = eval { $parsed_stylesheet->transform ($doc, %parameters) };
	$xslt_err = $!;
    } elsif (-e $document) {
	$results
	    = eval { $parsed_stylesheet->transform_file ($document, %parameters) };
	$xslt_err = $!;
    } else {
	# default: guess that $document is a string
	my $doc = XML::LibXML->load_xml (string => $document);
	$results = eval { $parsed_stylesheet->transform ($doc, %parameters) };
	$xslt_err = $!;
    }

    if (! defined $results) {
	croak error_message ('We failed to apply the stylesheet', $LF, $LF, $SP, $SP, $stylesheet, $LF, $LF, 'to', $LF, $LF, $SP, $SP, $document, $SP, '.', $LF, $LF, 'The stylesheet appears to be a valid XML file.  Is the input document valid XML?  The error we got was:', $LF, $LF, $xslt_err);
    }

    my $result_bytes = $parsed_stylesheet->output_as_bytes ($results);

    if (defined $result_path) {
	open (my $result_fh, '>', $result_path);
	print {$result_fh} $result_bytes;
	close $result_fh;
    }

    if (wantarray) {
	return split ("\N{LF}", $result_bytes);
    } else {
	return $result_bytes;
    }

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

sub strip_extension {
    my $path = shift;
    return $path =~ / (.+) [.][^.]+ \z / ? $1 : $path;
}

sub is_valid_xml_file {
    my $path = shift;

    if (! -e $path) {
	return 0;
    }

    if (! -r $path) {
	return 0;
    }

    my $xmllint_status = system ("xmllint --noout ${path} > /dev/null 2>&1");
    my $xmllint_exit_code = $xmllint_status >> 8;

    return $xmllint_exit_code == 0 ? 1 : 0;

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

    my $exit_code = ($tool_harness->results ())[0];

    return $exit_code == 0 ? 1 : 0;

}

sub slurp {
    my $path_or_fh = shift;

    open (my $fh, '<', $path_or_fh)
	or die 'Error: unable to open the file (or filehandle) ', $path_or_fh, '.';

    my $contents;
    { local $/; $contents = <$fh>; }

    close $fh
	or die 'Error: unable to close the file (or filehandle) ', $path_or_fh, '.';

    if (wantarray) {
	return split ($LF, $contents);
    } else {
	return $contents;
    }
}

sub normalize_term_or_formula {
    my $node = shift;
    my @variables = @_;
    my $node_name = $node->nodeName ();
    if ($node_name eq 'variable') {
	my $variable_name = $node->findvalue ('@name');
	my $index = first_index { $_ eq $variable_name } @variables;
	if ($index < 0) {
	    die error_message ('We cannot find ', $variable_name, ' in the list ', Dumper (@variables));
	}
	my $new_variable = XML::LibXML::Element->new ('variable');
	my $new_name_attribute = XML::LibXML::Attr->new ('name', "V${index}");
	$new_variable->addChild ($new_name_attribute);
	return $new_variable;
    } else {
	my $new_node = $node->cloneNode (0);
	my @children = $node->childNodes ();
	my @normalized_children
	    = map { normalize_term_or_formula ($_, @variables) } @children;
	foreach my $child (@normalized_children) {
	    $new_node->addChild ($child);
	}
	return $new_node;
    }
}

sub normalize_tptp_formula_node {
    my $formula_node = shift;
    my $normalized_formula_node = XML::LibXML::Element->new ('formula');

    # Attributes
    foreach my $attribute ($formula_node->attributes ()) {
    	$normalized_formula_node->addChild ($attribute->cloneNode ());
    }

    (my $formula_proper_node) = $formula_node->findnodes ('*[1]');
    my @variables = $formula_proper_node->findnodes ('descendant::variable');
    my %variables = ();
    my @variables_no_repetitions = ();
    foreach my $variable (@variables) {
	my $variable_name = $variable->findvalue ('@name');
	if (defined $variables{$variable_name}) {
	    # ship
	} else {
	    push (@variables_no_repetitions, $variable_name);
	    $variables{$variable_name} = 0;
	}
    }

    # warn 'variables without repetitions:', $LF, Dumper (@variables_no_repetitions);

    my $normalized_formula_proper = normalize_term_or_formula ($formula_proper_node, @variables_no_repetitions);
    $normalized_formula_node->appendChild ($normalized_formula_proper);

    # source
    if ($formula_node->exists ('source')) {
	(my $source) = $formula_node->findnodes ('source');
	$normalized_formula_node->appendChild ($source->cloneNode (1));
    }

    # useful-info
    if ($formula_node->exists ('useful-info')) {
	(my $useful_info) = $formula_node->findnodes ('useful-info');
	$normalized_formula_node->appendChild ($useful_info->cloneNode (1));
    }

    return $normalized_formula_node;
}

sub normalize_variables {
    my $tptp_file = shift;
    my $parser = XML::LibXML->new ();
    my $tptp_document = is_file ($tptp_file) ? $parser->parse_file ($tptp_file)
	: $parser->parse_string ($tptp_file);
    my $normalized_tptp_document = XML::LibXML::Document->createDocument ();
    my $normalized_tptp_root = XML::LibXML::Element->new ('tstp');
    $normalized_tptp_document->setDocumentElement ($normalized_tptp_root);
    foreach my $formula_node ($tptp_document->findnodes ('/tstp/formula')) {
	my $normalized_formula_node = normalize_tptp_formula_node ($formula_node);
	$normalized_tptp_root->appendChild ($normalized_formula_node);
	$normalized_tptp_document->importNode ($normalized_formula_node);
    }

    my $tptp_document_as_string = $normalized_tptp_document->toString (1);

    if (is_file ($tptp_file)) {
	open (my $tptp_fh, '>', $tptp_file)
	    or die error_message ('Unable to open an output filehandle for', $SP, $tptp_file);
	say {$tptp_fh} $tptp_document_as_string
	    or die error_message ('Unable to write the normalized contents of', $SP, $tptp_file);
	close $tptp_fh
	    or die error_message ('Unable to close the output filehandle for', $SP, $tptp_file);
    }

    return $tptp_document_as_string;
}

sub tptp_xmlize {
    my $tptp_file = shift;
    my $output_path = shift;

    my $tptp4X_errs = $EMPTY_STRING;
    my $tptp4X_out = $EMPTY_STRING;
    my @tptp4X_call = ('tptp4X', '-N', '-V', '-c', '-x', '-fxml', '--');

    my $tptp4X_harness = undef;
    if (is_file ($tptp_file)) {
	$tptp4X_harness = harness (\@tptp4X_call,
				   '<', $tptp_file,
				   '>', \$tptp4X_out,
				   '2>', \$tptp4X_errs);
    } else {
	$tptp4X_harness = harness (\@tptp4X_call,
				   '<', \$tptp_file,
				   '>', \$tptp4X_out,
				   '2>', \$tptp4X_errs);
    }

    $tptp4X_harness->start ();
    $tptp4X_harness->finish ();

    my $tptp4X_exit_code = ($tptp4X_harness->results)[0];

    if ($tptp4X_exit_code != 0) {
	confess ('tptp4X did not terminate cleanly when XMLizing', $LF, $LF, $SP, $SP, $tptp_file, $SP, '.', $LF, $LF, 'Its exit code was', $SP, $tptp4X_exit_code, '.');
    }

    if (defined $output_path) {
	open (my $tptp_fh, '>', $output_path)
	    or confess 'Unable to open an output filehandle for', $SP, $output_path;
	say {$tptp_fh} $tptp4X_out
	    or confess 'Unable to print to the output filehandle for', $SP, $output_path;
	close $tptp_fh
	    or confess 'Unable to close the output filehandle for', $SP, $output_path;
    }

    return $tptp4X_out;

}

sub tptp_fofify {
    my $tptp_file = shift;
    my $output_path = shift;

    my $tptp4X_errs = $EMPTY_STRING;
    my $tptp4X_out = $EMPTY_STRING;
    my @tptp4X_call = ('tptp4X', '-tfofify', '--');

    my $tptp4X_harness = undef;
    if (is_file ($tptp_file)) {
	$tptp4X_harness = harness (\@tptp4X_call,
				   '<', $tptp_file,
				   '>', \$tptp4X_out,
				   '2>', \$tptp4X_errs);
    } else {
	$tptp4X_harness = harness (\@tptp4X_call,
				   '<', \$tptp_file,
				   '>', \$tptp4X_out,
				   '2>', \$tptp4X_errs);
    }

    $tptp4X_harness->start ();
    $tptp4X_harness->finish ();

    my $tptp4X_exit_code = ($tptp4X_harness->results)[0];

    if ($tptp4X_exit_code != 0) {
	confess ('tptp4X did not terminate cleanly when XMLizing', $SP, $tptp_file, '. Its exit code was', $SP, $tptp4X_exit_code, '.  Its output was:', $LF, $tptp4X_out);
    }

    if (defined $output_path) {
	open (my $tptp_fh, '>', $output_path)
	    or confess 'Unable to open an output filehandle for', $SP, $output_path;
	say {$tptp_fh} $tptp4X_out
	    or confess 'Unable to print to the output filehandle for', $SP, $output_path;
	close $tptp_fh
	    or confess 'Unable to close the output filehandle for', $SP, $output_path;
    }

    return $tptp4X_out;

}

sub run_harness {
    my $call_ref = shift;
    my $input = shift;

    my $output = $EMPTY_STRING;
    my $error = $EMPTY_STRING;

    my @call = @{$call_ref};

    my $harness = undef;

    if (defined $input) {
	$harness = harness (\@call,
			    '<', \$input,
			    '>', \$output,
			    '2>', \$error);
    } else {
	$harness = harness (\@call,
			    '>', \$output,
			    '2>', \$error);
    }

    $harness->start ();
    $harness->finish ();

    my $exit_code = ($harness->results)[0];

    if ($exit_code != 0) {
	my $program_name = $call[0];
	confess ($program_name, $SP, 'did not exit cleanly. It was called like this:', $LF, $LF, $SP, $SP, join ($SP, @call), $LF, $LF, 'Its exit code was', $SP, $exit_code, '. Here it its error output:', $error, $LF);
    }

    return $output;

}

sub is_file {
    my $thing = shift;

    my $lf_index = index ($thing, $LF);

    if ($lf_index < 0) {
	return (-f $thing ) ? 1 : 0;
    } else {
	return 0;
    }

}

sub sort_tstp_solution {
    my $solution = shift;

    my $solution_copy = $solution; # the harness can eat our variable! save a copy

    # Sort
    my $dependencies_str = undef;
    my @xsltproc_deps_call = ('xsltproc', $DEPENDENCIES_STYLESHEET, '-');
    my @tsort_call = ('tsort');

    my $sort_harness = 	harness (\@xsltproc_deps_call,
				 '<',
				 (is_file ($solution) ? $solution : \$solution),
				 '|',
				 \@tsort_call,
				 '>', \$dependencies_str);


    $sort_harness->start ();
    $sort_harness->finish ();

    my @dependencies = split ($LF, $dependencies_str);
    my $dependencies_token_string = ',' . join (',', @dependencies) . ',';

    return apply_stylesheet ($SORT_TSTP_STYLESHEET,
			     $solution_copy,
			     (is_file ($solution_copy) ? $solution_copy : undef),
			     { 'ordering' => $dependencies_token_string });

}

sub normalize_tstp_steps {
    my $solution = shift;

    return scalar apply_stylesheet ($NORMALIZE_STEPS_STYLESHEET,
				    $solution);
}

sub list_to_token_string {
    my @items = @_;
    if (scalar @items == 0) {
	',,';
    } else {
	',' . join (',', @items) . ',';
    }
}

sub items_of_token_string {
    my $token_string = shift;

    my @items = ();

    if ($token_string eq ',,') {
	if (wantarray) {
	    return @items;
	} else {
	    return \@items;
	}
    } else {
	if ($token_string =~ /\A [,] (.+) [,] \z /) {
	    my $trimmed_token_string = $1;
	    return split (',', $trimmed_token_string);
	} else {
	    confess 'Unable to make sense of the token string \'', $token_string, '\'.';
	}
    }
}

1;
__END__
