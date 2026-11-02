use strict;use warnings;
use Test::More;
use FindBin;
use Template;
my $r="$FindBin::Bin/..";
my $reference=$ENV{ACT_REFERENCE_LIB} || '/opt/pcc-browser/act-reference/lib';
$reference=~s{/lib/?$}{};
my $tt=Template->new({INCLUDE_PATH=>["$r/theme/actdocs/templates","$reference/conferences/demo/actdocs/templates","$reference/templates"],ENCODING=>'UTF-8'});
for my $admin(0,1){
 my $html;
 $tt->process('menu',{global=>{config=>{talks_show_schedule=>0},request=>{user=>{is_talks_admin=>$admin,is_admin=>$admin,has_registered=>1}}},
 make_uri=>sub{'/conference/'.$_[0]}},\$html) or die $tt->error;
 like($html,qr{href="/conference/talks"},'Presentations heading keeps the talks link');
 if($admin){
  like($html,qr{href="/conference/talks">\s*Manage talks\s*</a>},'explicit Manage talks link visible for talk admin');
  like($html,qr{href="/conference/schedule"},'schedule admin link retained');
  like($html,qr{href="/conference/tracks"},'track admin link retained');
  like($html,qr{href="/conference/export_talks"},'CSV admin link retained');
  like($html,qr{href="/conference/rights"},'rights management retained');
 }else{
  unlike($html,qr/Manage talks/,'Manage talks hidden from ordinary users');
  unlike($html,qr{href="/conference/tracks"},'track administration hidden from ordinary users');
 }
}
done_testing;
