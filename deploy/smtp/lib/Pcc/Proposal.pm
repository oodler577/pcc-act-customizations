package Pcc::Proposal;
use strict;
use utf8;
use warnings;
use JSON::PP ();
my $json = JSON::PP->new->canonical->pretty;
my $start = '[PCC proposal details v1]';
my $end = '[/PCC proposal details]';
our @fields = qw(delivery timezone morning afternoon evening availability qa qa_notes ai_extent ai_percent ai_basis ai_generated human_contribution verification longer_minutes ai_notes);
my %choices = (
 delivery => [qw(in_person live_remote prerecorded)],
 qa => [qw(yes no unsure)],
 ai_extent => [qw(none minor substantial predominant)],
 morning => [qw(1)], afternoon => [qw(1)], evening => [qw(1)],
);
sub unpack_comment {
 my ($comment) = @_;
 $comment //= '';
 my $data = {};
 if ($comment =~ /\Q$start\E\n(.*?)\n\Q$end\E\s*\z/s) {
   my $raw = $1;
   $data = eval { $json->decode($raw) };
   die "Cannot read saved PCC proposal details; no changes made\n"
     unless ref($data) eq 'HASH' && !grep { ref($_) } values %$data;
   $comment =~ s/\n*\Q$start\E\n.*?\n\Q$end\E\s*\z//s;
 }
 return ($comment, $data);
}
sub from_args {
 my ($args, %options) = @_;
 my (%data, @errors);
 for my $key (@fields) {
   next if $key eq 'ai_notes' && !exists $args->{pcc_ai_notes};
   next if $key =~ /^(?:ai_extent|ai_percent|ai_basis|ai_generated|human_contribution|verification)$/ && !exists $args->{"pcc_$key"};
   my $v = $args->{"pcc_$key"} // '';
   if (ref($v)) { push @errors, "Invalid $key."; next }
   $v =~ s/^\s+|\s+$//g;
   $data{$key} = $v;
   push @errors, "Please shorten $key (maximum 4000 characters)." if length($v)>4000;
   push @errors, "Invalid $key." if $v =~ /\x00/;
   if ($v ne '' && $choices{$key}) {
     push @errors, "Please choose a valid $key." unless grep { $_ eq $v } @{$choices{$key}};
   }
 }
 for my $key(qw(delivery timezone)) {
   push @errors, "Please complete ".($key =~ s/_/ /gr)."." unless length($data{$key}) || $options{allow_incomplete};
 }
 if ($data{timezone} ne '') {
   require DateTime::TimeZone;
   push @errors, 'Choose a valid IANA time zone, such as America/Chicago.'
     unless DateTime::TimeZone->is_valid_name($data{timezone}) && $data{timezone} ne 'floating';
 }
 if (($data{delivery} // '') eq 'prerecorded') {
   push @errors, 'Please indicate your availability for live questions.' unless $data{qa} || $options{allow_incomplete};
 } else { $data{qa} = ''; $data{qa_notes} = '' }
 if ($data{longer_minutes} ne '') {
   push @errors, 'Requested longer duration must be 56 to 240 minutes.'
     unless $data{longer_minutes} =~ /^\d+$/ && $data{longer_minutes}>=56 && $data{longer_minutes}<=240;
 }
 return (\%data,\@errors);
}
sub pack_comment {
 my ($comment,$data) = @_;
 # Remove only our trailing block; preserve ordinary comments and unknown keys.
 my ($plain,$old) = unpack_comment($comment);
 my %merged = (%$old,%$data);
 $plain =~ s/\s+\z//;
 return $plain . "\n\n$start\n" . $json->encode(\%merged) . "$end\n";
}
sub ai_notes {
 my ($data) = @_;
 return $data->{ai_notes} if exists $data->{ai_notes};
 my @lines;
 for my $pair (
  ['ai_extent','Extent'], ['ai_percent','Estimated AI percentage'],
  ['ai_basis','Percentage basis'], ['ai_generated','AI work'],
  ['human_contribution','Presenter work'], ['verification','Verification']
 ) {
   push @lines, "$pair->[1]: $data->{$pair->[0]}"
     if defined($data->{$pair->[0]}) && length($data->{$pair->[0]});
 }
 return join "\n", @lines;
}
sub timezone_groups {
 my ($saved) = @_;
 require DateTime::TimeZone;
 my @common=(
 ['UTC','UTC'],
 ['America/New_York','US Eastern — New York'],
 ['America/Chicago','US Central — Chicago'],
 ['America/Denver','US Mountain — Denver'],
 ['America/Phoenix','Arizona — Phoenix'],
 ['America/Los_Angeles','US Pacific — Los Angeles'],
 ['America/Anchorage','Alaska — Anchorage'],
 ['Pacific/Honolulu','Hawaii — Honolulu'],
 ['America/Toronto','Canada Eastern — Toronto'],
 ['America/Vancouver','Canada Pacific — Vancouver'],
 ['America/Mexico_City','Mexico City'],
 ['America/Sao_Paulo','Brazil — São Paulo'],
 ['Europe/London','UK — London'],
 ['Europe/Paris','Central Europe — Paris'],
 ['Europe/Helsinki','Eastern Europe — Helsinki'],
 ['Africa/Johannesburg','South Africa — Johannesburg'],
 ['Asia/Kolkata','India — Kolkata'],
 ['Asia/Singapore','Singapore'],
 ['Asia/Shanghai','China — Shanghai'],
 ['Asia/Tokyo','Japan — Tokyo'],
 ['Australia/Perth','Australia Western — Perth'],
 ['Australia/Sydney','Australia Eastern — Sydney'],
 ['Pacific/Auckland','New Zealand — Auckland'],
 );
 my %seen=map { $_->[0]=>1 } @common;
 my @groups=({label=>'Common time zones',options=>[map {{name=>$_->[0],label=>$_->[1]}} @common]});
 my @others=map {my $label=$_; $label=~s/_/ /g; {name=>$_,label=>$label}}
   grep {!$seen{$_}++} sort DateTime::TimeZone->all_names;
 if ($saved && !$seen{$saved} && DateTime::TimeZone->is_valid_name($saved)) {
   push @others,{name=>$saved,label=>$saved.' (saved time zone)'};
 }
 push @groups,{label=>'All other regions',options=>\@others};
 return \@groups;
}
1;
