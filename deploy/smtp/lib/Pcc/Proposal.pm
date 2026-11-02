package Pcc::Proposal;
use strict;
use warnings;
use JSON::PP ();
my $json = JSON::PP->new->canonical->pretty;
my $start = '[PCC proposal details v1]';
my $end = '[/PCC proposal details]';
our @fields = qw(talk_type delivery timezone morning afternoon evening availability qa qa_notes ai_extent ai_percent ai_basis ai_generated human_contribution verification longer_minutes);
my %choices = (
 talk_type => [qw(science talk_only)],
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
 for my $key(qw(talk_type delivery timezone ai_extent)) {
   push @errors, "Please complete ".($key =~ s/_/ /gr)."." unless length($data{$key}) || $options{allow_incomplete};
 }
 if ($data{timezone} ne '') {
   require DateTime::TimeZone;
   push @errors, 'Choose a valid IANA time zone, such as America/Chicago.'
     unless DateTime::TimeZone->is_valid_name($data{timezone}) && $data{timezone} ne 'floating';
 }
 if ($data{delivery} eq 'prerecorded') {
   push @errors, 'Please indicate your availability for live questions.' unless $data{qa} || $options{allow_incomplete};
 } else { $data{qa} = ''; $data{qa_notes} = '' }
 if ($data{ai_percent} ne '') {
   push @errors, 'AI percentage must be a number from 0 to 100.'
     unless $data{ai_percent} =~ /^(?:100|[0-9]{1,2})(?:\.\d+)?$/ && $data{ai_percent}<=100;
   push @errors, 'Explain what your AI percentage measures.' unless $data{ai_basis};
 }
 if (!$options{allow_incomplete} && $data{ai_extent} ne '' && $data{ai_extent} ne 'none') {
   push @errors, 'Describe the AI contribution and your own contribution.'
     unless $data{ai_generated} && $data{human_contribution};
 }
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
1;
