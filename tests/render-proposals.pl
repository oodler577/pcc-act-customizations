use strict;use warnings;use utf8;use Template;use File::Path qw(make_path);use File::Copy qw(copy);use HTML::Entities qw(encode_entities);
use FindBin;use lib "$FindBin::Bin/../deploy/smtp/lib";use Pcc::Proposal;
use FindBin;
my $r="$FindBin::Bin/../theme";my $d=shift or die "Usage: render-proposals.pl OUTPUT_DIRECTORY\n";
my $reference=$ENV{ACT_REFERENCE_LIB} || '/opt/pcc-browser/act-reference/lib';
$reference =~ s{/lib/?$}{};
make_path("$d/conference/css","$d/conference/images","$d/conference/fonts","$d/mock");
open my $f,'<:encoding(UTF-8)',"$r/actdocs/templates/talk/add" or die $!;local $/;my $text=<$f>;
$text =~ s/\{\{(.*?)\}\}/$1/sg;
my $tt=Template->new({INCLUDE_PATH=>["$r/actdocs/templates","$r/actdocs/static","$reference/conferences/demo/actdocs/templates","$reference/templates","$d/mock"],ABSOLUTE=>1,ENCODING=>'UTF-8',FILTERS=>{form_unescape=>sub{$_[0]}}});
for my $mode(qw(new edit admin error)) {
 my %pcc=(delivery=>'prerecorded',timezone=>'America/Chicago',qa=>'yes',ai_extent=>'substantial',ai_percent=>'20',ai_basis=>'Example code',ai_notes=>encode_entities('<script>alert(1)</script>'),human_contribution=>'Designed, tested, and integrated',verification=>'Compared results',morning=>1);
 my $html;
 $tt->process(\$text,{
  title=>'Example Perl talk',abstract=>'An abstract',comment=>'Organizer note',duration=>30,
  ($mode ne 'new'?(talk_id=>1,pcc=>\%pcc):()),
  ($mode eq 'error'?(pcc_errors=>['Please indicate your availability for live questions.']):()),
  users=>[{user_id=>1,first_name=>'Test',last_name=>'Speaker'}],tracks=>[],rooms=>{},dates=>[],
  timezone_groups=>Pcc::Proposal::timezone_groups('America/Chicago'),
  global=>{config=>{talks_durations=>{30=>1,55=>1},talks_languages=>{en=>'English'}},request=>{language=>'en',base_url=>'',r=>{uri=>'/conference/newtalk'},user=>{is_talks_admin=>$mode eq 'admin',user_id=>1}},news=>sub{return []}},
  loc=>sub{$_[0]},make_uri=>sub{return '/conference/'.$_[0]},make_uri_info=>sub{return '/conference/'.join('/',@_) }
 },\$html) or die $tt->error;
 open my $out,'>:encoding(UTF-8)',"$d/conference/proposal-$mode.html" or die $!; print $out $html; close $out;
}
copy("$r/wwwdocs/css/style.css","$d/conference/css/style.css") or die $!;
for my $f(qw(pcc-oyster-156.webp pcc-social.jpg)){copy("$r/wwwdocs/images/$f","$d/conference/images/$f") or die $!;}
for my $f(qw(noto-sans-regular.woff2 noto-sans-700.woff2)){copy("$r/wwwdocs/fonts/$f","$d/conference/fonts/$f") or die $!;}
print "Rendered proposal states.\n";
