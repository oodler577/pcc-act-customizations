#!/usr/bin/env perl
use strict;use warnings;
use FindBin;use lib "$FindBin::Bin/lib";
use Pcc::Deploy qw(read_text read_bytes run decode_json_text deployment);
use Digest::SHA qw(sha256_hex);
my $source=deployment(shift // die "Usage: $0 ACT_SOURCE\n");die "Unexpected arguments\n" if @ARGV;
my $lock=decode_json_text(read_text("$FindBin::Bin/../upstream-lock.json"));
my $commit=run('git','-C',$source,'rev-parse','HEAD');chomp $commit;
my @changed;
for my $name(sort keys %{$lock->{upstream_files}}){
 my $expected=$lock->{upstream_files}{$name};
 my $actual=-f "$source/$name" ? sha256_hex(read_bytes("$source/$name")) : undef;
 push @changed,$name if defined($expected)!=defined($actual) || (defined($actual) && $actual ne $expected);
}
print "Pinned ACT: $lock->{act_commit}\nCandidate: $commit\n";
if(@changed){print "Review upstream changes against local overrides:\n";print " - $_\n" for @changed}
else{print "Tracked upstream files match the reviewed baseline.\n"}
print "Different ACT revision: full upgrade checks are required even if tracked files match.\n" if $commit ne $lock->{act_commit};
exit(@changed ? 1 : 0);
