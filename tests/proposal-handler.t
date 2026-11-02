use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../deploy/smtp/lib";
use lib $ENV{ACT_REFERENCE_LIB} || '/opt/pcc-browser/act-reference/lib';
use DateTime;
our (%Request,$Config,$talk,$view,$created,@saved_tags,$updated_tags);
BEGIN {
 for my $name(qw(Config Handler Email Handler/Talk/Util I18N Tag Talk Template/HTML Template Track User Util)) {
   $INC{"Act/$name.pm"}=__FILE__;
 }
 package Act::Config;
 sub import { my $c=caller; no strict 'refs'; *{$c.'::Request'}=\%main::Request; *{$c.'::Config'}=\$main::Config }
 package Act::Handler;
 package Act::Email;
 package Act::Handler::Talk::Util;
 sub notify_accept {}
 package Act::I18N;
 package Act::Tag;
 sub split_tags { split /\s+/, ($_[1] || '') } sub fetch_tags { @main::saved_tags } sub update_tags { shift; my %args=@_; $main::updated_tags=join ' ',@{$args{newtags}} }
 package Act::Talk;
 sub new { $main::talk }
 sub create { shift; $main::created++; $main::talk=bless {talk_id=>1,@_},__PACKAGE__ }
 sub update { my $s=shift; %$s=(%$s,@_) }
 sub clone { bless {%{$_[0]}},__PACKAGE__ }
 sub AUTOLOAD { our $AUTOLOAD; (my $k=$AUTOLOAD)=~s/.*:://; return if $k eq 'DESTROY'; $_[0]{$k} }
 package Act::Template::HTML;
 sub new { $main::view=bless {vars=>{}},__PACKAGE__ }
 sub variables { my $s=shift; %{$s->{vars}}=(%{$s->{vars}},@_) }
 sub process { $_[0]{processed}=$_[1] }
 package Act::Template;
 package Act::Track;
 sub get_tracks { [] }
 package Act::User;
 sub get_users { [] }
 sub new { bless {},__PACKAGE__ }
 sub participation { 1 }
 package Act::Util;
 sub import {
   my $c=caller; no strict 'refs';
   *{$c.'::format_datetime_string'}=sub { my ($y,$m,$d)=split /-/,substr($_[0],0,10); DateTime->new(year=>$y,month=>$m,day=>$d) };
   *{$c.'::make_uri'}=sub { '/conference/'.$_[0] };
 }
 sub redirect { $_[0] }
 package TestConfig;
 sub talks_start_date {'2027-01-01'} sub talks_end_date {'2027-01-02'}
 sub talks_submissions_open {1} sub talks_edition_open {1}
 sub talks_durations {{30=>1,55=>1}} sub talks_languages {{en=>'English'}}
 sub talks_levels {0} sub talks_submissions_notify_address {''}
 sub rooms {{1=>'Room'}}
 package TestUser;
 sub is_talks_admin {$_[0]{admin}||0} sub user_id {2} sub has_registered {1}
 package TestRequest;
 sub header_in {''}
}
require "$FindBin::Bin/../deploy/smtp/lib/Act/Handler/Talk/Edit.pm";
$Config=bless {},'TestConfig';
sub request {
 my ($args,$admin)=@_;
 %Request=(args=>$args,conference=>'conference',user=>bless({admin=>$admin},'TestUser'),r=>bless({},'TestRequest'));
 Act::Handler::Talk::Edit::handler();
}
my %base=(submit=>1,title=>'A useful Perl talk',abstract=>'Perl techniques',duration=>30,
 comment=>'Please avoid Friday',lang=>'en',pcc_version=>1,
 pcc_delivery=>'prerecorded',pcc_timezone=>'Europe/London',pcc_qa=>'yes',pcc_ai_extent=>'none');
request({%base});
is($created,1,'new talk created through patched handler');
is($talk->duration,30,'native duration saved');
is($talk->room,1,'new talk assigned the sole configured room');
is($view->{processed},'talk/added','native success page');
my ($plain,$details)=Pcc::Proposal::unpack_comment($talk->comment);
is($plain,'Please avoid Friday','ordinary comment saved');
is($details->{qa},'yes','recorded Q&A saved');
request({talk_id=>1});
is($view->{vars}{pcc}{timezone},'Europe/London','edit GET restores saved details');
is($view->{vars}{comment},'Please avoid Friday','edit comment excludes metadata block');
request({%base,talk_id=>1,abstract=>'',pcc_qa=>'no',comment=>'New note'});
is($view->{vars}{pcc}{qa},'no','failed edit retains submitted Q&A');
is($view->{vars}{comment},'New note','failed edit retains submitted comments');
is($view->{vars}{abstract},'','failed edit retains empty required field');
is((Pcc::Proposal::unpack_comment($talk->comment))[1]{qa},'yes','failed validation does not save');
request({%base,talk_id=>1,pcc_qa=>'no',comment=>'Updated note',duration=>55});
is($talk->duration,30,'speaker cannot change organizer assigned duration');
is((Pcc::Proposal::unpack_comment($talk->comment))[1]{qa},'no','successful edit updates Q&A');
request({%base,talk_id=>1,pcc_qa=>'',comment=>'Bad Q&A'});
ok(@{$view->{vars}{pcc_errors}},'server rejects missing prerecorded Q&A');
is((Pcc::Proposal::unpack_comment($talk->comment))[0],'Updated note','invalid metadata does not overwrite comments');
request({%base,talk_id=>1,user_id=>2,duration=>55,track_id=>7,accepted=>1},1);
is($talk->duration,55,'organizer can change duration');
is($talk->track_id,7,'organizer track assignment retained');
ok($talk->accepted,'organizer can accept talk');
my %legacy=(%base,talk_id=>1,comment=>'Legacy form comment',user_id=>2,duration=>55,track_id=>7);
delete $legacy{pcc_version};
request(\%legacy,1);
is((Pcc::Proposal::unpack_comment($talk->comment))[1]{qa},'yes','older forms preserve stored details');
request({submit=>1,talk_id=>1,title=>'Legacy proposal',abstract=>'Existing abstract',duration=>55,lang=>'en',user_id=>2,pcc_version=>1},1);
is_deeply($view->{vars}{pcc_errors},[],'organizer may maintain a legacy talk with incomplete new metadata');
is($talk->title,'Legacy proposal','organizer edit saved without fabricated speaker answers');
$talk->{url_video1}='https://example.invalid/existing-recording';
$talk->{allow_record}=0;
$talk->{room}=1;
@saved_tags=('perl','science');
request({%base,talk_id=>1,pcc_version=>2,user_id=>2,comment=>'Keep metadata',pcc_ai_notes=>'I tested AI generated code.'},1);
is($talk->url_video1,'https://example.invalid/existing-recording','hidden video URLs preserved');
is($updated_tags,'perl science','hidden tags preserved');
is($talk->lang,'en','English stored automatically');
is($talk->room,1,'existing room assignment preserved with hidden control');
is($talk->allow_record,0,'organizer edit does not invent prior recording consent');
request({%base,talk_id=>1,pcc_version=>2,pcc_ai_notes=>'No AI used.'});
is($talk->allow_record,1,'speaker submission confirms stated recording requirement');
is((Pcc::Proposal::unpack_comment($talk->comment))[1]{ai_notes},'No AI used.','combined effort comment saved');
done_testing;
