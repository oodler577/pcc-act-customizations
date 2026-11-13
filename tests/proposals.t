use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../deploy/smtp/lib";
use Pcc::Proposal;
my %args=(
 pcc_delivery=>'prerecorded',
 pcc_timezone=>'America/Chicago',pcc_qa=>'yes',
 pcc_ai_notes=>"AI drafted code; I designed the approach and verified it.\nAbout a quarter of the example code.",
 pcc_morning=>'1',pcc_availability=>"Friday\nbefore 11 am",
);
my ($data,$errors)=Pcc::Proposal::from_args(\%args);
is_deeply($errors,[],'valid simplified proposal');
my $stored=Pcc::Proposal::pack_comment('Ordinary comments',$data);
my ($plain,$restored)=Pcc::Proposal::unpack_comment($stored);
is($plain,'Ordinary comments','ordinary comments preserved');
is_deeply($restored,$data,'all answers round trip');
is(Pcc::Proposal::pack_comment($stored,$data),$stored,'repeat save does not duplicate block');
my $future=Pcc::Proposal::pack_comment($stored,{future_key=>'keep me'});
my (undef,$new)=Pcc::Proposal::unpack_comment(Pcc::Proposal::pack_comment($future,$data));
is($new->{future_key},'keep me','unknown keys preserved');
my ($old,$empty)=Pcc::Proposal::unpack_comment('Legacy comments');
is($old,'Legacy comments','legacy comments untouched');
is_deeply($empty,{},'legacy proposal has empty details');
for my $case(
 ['pcc_timezone','Moon/Base','invalid time zone'],
 ['pcc_delivery','invalid','invalid delivery'],
 ['pcc_qa','','Q&A required for recorded talks'],
 ['pcc_availability','x'x4001,'text length limited'],
 ['pcc_ai_notes','x'x4001,'AI comment length limited'],
 ['pcc_ai_notes',[],'AI array input rejected'],
 ['pcc_delivery',[],'array input rejected'],
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
is_deeply($admin_errors,[],'organizers may maintain legacy proposals');
my %legacy=(ai_extent=>'minor',ai_percent=>'20',ai_basis=>'Lines',ai_generated=>'Draft code',human_contribution=>'Design',verification=>'Tests');
my $combined=Pcc::Proposal::ai_notes(\%legacy);
like($combined,qr/AI work: Draft code/,'old AI work shown in combined box');
like($combined,qr/Presenter work: Design/,'old human work shown in combined box');
is(Pcc::Proposal::ai_notes({%legacy,ai_notes=>'New combined comment'}),'New combined comment','new comment takes precedence');
my (undef,$merged)=Pcc::Proposal::unpack_comment(Pcc::Proposal::pack_comment(Pcc::Proposal::pack_comment('',\%legacy),$data));
is($merged->{ai_generated},'Draft code','simplified save preserves legacy AI keys');
my $groups=Pcc::Proposal::timezone_groups('US/Central');
my @zones=map {@{$_->{options}}} @$groups;
my %counts; $counts{$_->{name}}++ for @zones;
is($counts{'America/Chicago'},1,'Central timezone exists once');
is($counts{'UTC'},1,'UTC offered');
is($counts{'US/Central'},1,'saved timezone aliases remain selectable');
ok(@zones>100,'worldwide standard timezone options');
my ($current,$current_errors)=Pcc::Proposal::from_args({%args,pcc_longer_minutes=>'75'});
is_deeply($current_errors,[],'obsolete custom duration input ignored');
ok(!exists $current->{longer_minutes},'new custom duration requests are not stored');
my $previous=Pcc::Proposal::pack_comment('',{talk_type=>'science',longer_minutes=>'90'});
my (undef,$retained)=Pcc::Proposal::unpack_comment(Pcc::Proposal::pack_comment($previous,$current));
is($retained->{talk_type},'science','retired talk type metadata preserved');
is($retained->{longer_minutes},'90','existing custom duration request is preserved');
my ($paper,$paper_errors)=Pcc::Proposal::from_args({%args,pcc_paper_title=>'  A Perl research paper  '});
is_deeply($paper_errors,[],'paper title accepted');
is($paper->{paper_title},'A Perl research paper','paper title trimmed');
my (undef,$saved_paper)=Pcc::Proposal::unpack_comment(Pcc::Proposal::pack_comment('Note',$paper));
is($saved_paper->{paper_title},'A Perl research paper','paper title persists');
my ($older_form)=Pcc::Proposal::from_args(\%args);
my (undef,$kept_paper)=Pcc::Proposal::unpack_comment(Pcc::Proposal::pack_comment(Pcc::Proposal::pack_comment('',$paper),$older_form));
is($kept_paper->{paper_title},'A Perl research paper','older form preserves paper title');
for my $invalid ([], 'x'x4001) {
 my (undef,$errors)=Pcc::Proposal::from_args({%args,pcc_paper_title=>$invalid});
 ok(@$errors,'invalid paper title rejected');
}
my ($ack,$ack_errors)=Pcc::Proposal::from_args({%args,pcc_paperless_doi_ack_present=>1,pcc_paperless_doi_ack=>1});
is_deeply($ack_errors,[],'paperless DOI acknowledgment accepted');
my $ack_comment=Pcc::Proposal::pack_comment('',$ack);
is((Pcc::Proposal::unpack_comment($ack_comment))[1]{paperless_doi_ack},1,'acknowledgment persisted');
is((Pcc::Proposal::unpack_comment(Pcc::Proposal::pack_comment($ack_comment,$older_form)))[1]{paperless_doi_ack},1,'older forms retain acknowledgment');
my ($unchecked)=Pcc::Proposal::from_args({%args,pcc_paperless_doi_ack_present=>1});
is((Pcc::Proposal::unpack_comment(Pcc::Proposal::pack_comment($ack_comment,$unchecked)))[1]{paperless_doi_ack},'','unchecking clears acknowledgment');
my (undef,$bad_ack)=Pcc::Proposal::from_args({%args,pcc_paperless_doi_ack=>'yes'});
ok(@$bad_ack,'invalid acknowledgment rejected');
done_testing;
