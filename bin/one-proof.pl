#!/usr/bin/env perl

use strict;
use warnings;
require v5.10.0;
use feature 'say';
use charnames qw(:full);
use Regexp::DefaultFlags;

my $within_head = 0;
my $head_printed = 0;
my $within_first_proof = 0;
my $first_proof_printed = 0;

while (defined (my $line = <ARGV>)) {
    chomp $line;

    if ($line =~ /============================== \N{SPACE} Prover9 \N{SPACE} ===============================/) {
	$within_head = 1;
    }

    if ($within_head) {
	say $line;
    }

    if ($line =~ /============================== \N{SPACE} end \N{SPACE} of \N{SPACE} head \N{SPACE} ===========================/) {
	$within_head = 0;
	$head_printed = 1;
    }

    if (! $first_proof_printed) {
	if ($line =~ /============================== \N{SPACE} PROOF \N{SPACE} =================================/) {
	    $within_first_proof = 1;
	}
	if ($within_first_proof) {
	    say $line;
	}
	if ($line =~ /============================== \N{SPACE} end \N{SPACE} of \N{SPACE} proof \N{SPACE} ==========================/) {
	    $within_first_proof = 0;
	    $first_proof_printed = 1;
	}
    }
}
