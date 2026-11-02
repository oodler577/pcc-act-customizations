use strict;use warnings;
use Test::More;
use FindBin;use Template;
use lib "$FindBin::Bin/../scripts/lib";
use Pcc::Deploy qw(read_text);
my $r="$FindBin::Bin/..";
my $reference=$ENV{ACT_REFERENCE_LIB} || '/opt/pcc-browser/act-reference/lib';$reference=~s{/lib/?$}{};
my $tt=Template->new({INCLUDE_PATH=>["$r/theme/actdocs/templates","$reference/conferences/demo/actdocs/templates","$reference/templates"],ENCODING=>'UTF-8'});
my @flags=qw(is_admin is_talks_admin is_news_admin is_users_admin is_treasurer);
my %paths=(is_admin=>['rights'],is_talks_admin=>[qw(talks schedule tracks ical_import export_talks events newevent)],is_news_admin=>['newsadmin'],is_users_admin=>[qw(export confirm_attend create)],is_treasurer=>['payments','csv/payments','csv/payment_items']);
sub render {
 my ($id,$user,$published)=@_;
 my $html;
 $tt->process('menu',{global=>{conference=>{name=>'Test conference'},config=>{talks_show_schedule=>$published||0,talks_submissions_open=>1},request=>{conference=>$id,user=>$user}},
 make_uri=>sub{"/$id/".$_[0]},make_uri_info=>sub{"/$id/".join('/',@_)}},\$html) or die $tt->error;
 return $html;
}
for my $id(qw(conference winter2026)){
 for my $role('guest','member',@flags,'all'){
  my $user=$role eq 'guest'?undef:{has_registered=>1,participation=>1,login=>'test',user_id=>1,map {$_=>($role eq $_ || $role eq 'all')} @flags};
  my $html=render($id,$user,0);
  like($html,qr/Current Conference/,"$id $role: current conference heading");
  like($html,qr{href="https://conference.perlcommunity.org/winter2026/">Winter 2026</a>},"$id $role: current edition link");
  if($id eq 'conference'){
   unlike($html,qr{href="/conference/newtalk"},"$id $role: no general-site proposal link");
  }else{
   like($html,qr{href="/winter2026/newtalk"},"$id $role: edition proposal link retained");
  }
  my ($admin)=$html=~m{(<details class="admin-panel">.*?</details>)}s;
  my $public=$html;$public=~s{<details class="admin-panel">.*?</details>}{}s;
  my $has_right=$role ne 'guest' && $role ne 'member';
  is(defined($admin)?1:0,$has_right?1:0,"$id $role: Admin visibility follows role");
  for my $flag(@flags){
   for my $path(@{$paths{$flag}}){
    # Talks has a public list; Schedule may be published. All organizer actions
    # must also be in the Admin group when the corresponding right is present.
    if($role eq $flag || $role eq 'all'){
     like($admin||'',qr{href="/\Q$id\E/\Q$path\E"},"$id $role: $path in Admin");
    }elsif($path ne 'talks'){
     unlike($admin||'',qr{href="/\Q$id\E/\Q$path\E"},"$id $role: no unrelated $path tool");
    }
    next if $path eq 'talks';
    unlike($public,qr{href="/\Q$id\E/\Q$path\E"},"$id $role: $path outside public links");
   }
  }
  unlike($html,qr/<details class="admin-panel"[^>]*open/,"$id $role: tools start collapsed");
 }
}
my $published=render('winter2026',{has_registered=>1,participation=>1},1);
like($published,qr{href="/winter2026/schedule"},'published schedule remains public');
like($published,qr{href="/winter2026/myschedule"},'personal schedule remains public when published');
my $ui=read_text("$r/theme/actdocs/templates/ui");
like($ui,qr{class="brand" href="https://conference.perlcommunity.org/"},'brand always links to permanent main home');
like($ui,qr{class="nav-home" href="\[% pcc_home_uri \| html %\]"},'sidebar home retains edition context');
my $home=read_text("$r/theme/actdocs/static/index.html");
unlike($home,qr/aria-label="Current conference edition"/,'old detached announcement strip removed');
like($home,qr{<section class="hero">.*?class="hero-current-edition"}s,'current edition integrated into hero');
like($home,qr{href="https://conference.perlcommunity.org/winter2026/">Winter 2026 details &amp; registration},'main call to action leads to current edition');
done_testing;
