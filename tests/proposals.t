use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../deploy/smtp/lib";
use Pcc::Proposal;
my %args = (
 pcc_talk_type=>'science', pcc_delivery=>'prerecorded',
 pcc_timezone=>'America/Chicago',pcc_qa=>'yes',pcc_ai_extent=>'substantial',
 pcc_ai_generated=>'Drafted <code> & tests',pcc_human_contribution=>'Designed and checked results',
 pcc_ai_percent=>'25',pcc_ai_basis=>'Lines in the presented example',
 pcc_morning=>'1',pcc_availability=>"Friday\nbefore 11 am",
);
my ($data,$errors)=Pcc::Proposal::from_args(\%args);
is_deeply($errors,[],'valid complete proposal');
my $stored=Pcc::Proposal::pack_comment("Ordinary comments\n", $data);
my ($plain,$restored)=Pcc::Proposal::unpack_comment($stored);
is($plain,'Ordinary comments','ordinary comments preserved');
is_deeply($restored,$data,'all answers restored including multiline text');
is(Pcc::Proposal::pack_comment($stored,$data),$stored,'repeat save does not duplicate block');
my $future=Pcc::Proposal::pack_comment($stored,{future_key=>'keep me'});
my (undef,$new)=Pcc::Proposal::unpack_comment(Pcc::Proposal::pack_comment($future,$data));
is($new->{future_key},'keep me','unknown keys preserved');
my ($old,$empty)=Pcc::Proposal::unpack_comment('Legacy comments');
is($old,'Legacy comments','legacy comments untouched');
is_deeply($empty,{},'legacy proposal has empty details');
for my $case (
 ['pcc_timezone','Moon/Base','invalid time zone'],
 ['pcc_delivery','invalid','invalid delivery'],
 ['pcc_qa','','Q&A required for recorded talks'],
 ['pcc_ai_percent','101','percentage range'],
 ['pcc_ai_basis','','percentage needs denominator'],
 ['pcc_ai_generated','','AI disclosure requires AI work'],
 ['pcc_human_contribution','','AI disclosure requires human work'],
 ['pcc_availability','x'x4001,'text length limited'],
 ['pcc_longer_minutes','45','longer duration validated'],
 ['pcc_talk_type',[],'array input rejected'],
) {
 my %bad=(%args,$case->[0]=>$case->[1]);
 my (undef,$errs)=Pcc::Proposal::from_args(\%bad);
 ok(@$errs,$case->[2]);
}
my %live=(%args,pcc_delivery=>'live_remote',pcc_qa=>'yes',pcc_qa_notes=>'stale');
my ($l,$e)=Pcc::Proposal::from_args(\%live);
is_deeply($e,[],'live remote valid');
is($l->{qa},'','irrelevant Q&A cleared');
is($l->{qa_notes},'','irrelevant Q&A notes cleared');
eval { Pcc::Proposal::unpack_comment("[PCC proposal details v1]\nnot json\n[/PCC proposal details]\n") };
like($@,qr/Cannot read saved/,'malformed metadata fails closed');
my (undef,$admin_errors)=Pcc::Proposal::from_args({},allow_incomplete=>1);
is_deeply($admin_errors,[],'organizers can maintain legacy proposals without inventing speaker answers');
done_testing;
