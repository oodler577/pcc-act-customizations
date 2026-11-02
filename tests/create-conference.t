use strict;use warnings;use utf8;
use Test::More;use FindBin;use lib "$FindBin::Bin/../scripts/lib";
use Pcc::Deploy qw(read_text read_bytes write_text copy_file run attempt json decode_json_text);
use File::Temp qw(tempdir);use File::Path qw(make_path);use Cwd qw(abs_path);
plan skip_all=>'Conference setup performs root ownership operations' if $>;
my $r=abs_path("$FindBin::Bin/..");my $tmp=tempdir(CLEANUP=>1);make_path("$tmp/bin");
local $ENV{PATH}="$tmp/bin:$ENV{PATH}";local $ENV{PCC_EDITION_REPO}=$r;local $ENV{PCC_EDITION_TEST}=$tmp;
write_text("$tmp/bin/docker",<<'DOCKER');
#!/usr/bin/env perl
use strict;use warnings;use Digest::SHA;use JSON::PP;
my $cmd=join ' ',@ARGV;
if($cmd=~/config --quiet/){exit 0}
elsif($cmd=~/id -[ug]/){print "0\n"}
elsif($cmd=~/sha256_hex/){
 exit 1 if $ENV{PCC_STALE};
 for my $rel('Pcc/Proposal.pm','Act/Handler/Talk/Edit.pm'){
  open my $f,'<:raw',"$ENV{PCC_EDITION_REPO}/deploy/smtp/lib/$rel" or die $!;my $sha=Digest::SHA->new(256);$sha->addfile($f);print $sha->hexdigest,"\n";
 }
}
elsif($cmd=~/Act::Store::Database/){
 exit 1 if $ENV{PCC_DB_FAIL};
 open my $f,'>',"$ENV{PCC_EDITION_TEST}/db-call.json" or die $!;print $f encode_json(\@ARGV);close $f;
 print "Synthetic edition database setup accepted.\n";
}
elsif($cmd=~/restart act/){exit 0}
else{die "Unexpected Docker call\n"}
DOCKER
write_text("$tmp/bin/curl","#!/usr/bin/env perl\nprint '200';\n");chmod 0755,"$tmp/bin/docker","$tmp/bin/curl";
sub fixture {
 my ($name)=@_;my $d="$tmp/$name";make_path("$d/conf","$d/conferences/conference/actdocs/conf","$d/conferences/conference/actdocs/templates","$d/conferences/conference/wwwdocs/photos");
 write_text("$d/conf/act.ini","[general]\nconferences = conference older\n[database]\npasswd = synthetic-private\n");
 write_text("$d/conferences/conference/actdocs/conf/act.ini","[general]\nname_en = General PCC\nlanguages = en nl\ndefault_language = nl\ntimezone = Europe/Amsterdam\nfull_uri = https://example.invalid/conference/\n[registration]\nopen = 1\n[talks]\nstart_date = 2027-01-01\nend_date = 2027-01-02\nsubmissions_open = 1\n[rooms]\nrooms = r1 r2 r3\nr1_name_en = Room 1\n[payment]\nopen = 1\ntype = OLD\n");
 write_text("$d/conferences/conference/actdocs/templates/local-wrapper","Local wrapper\n");
 write_text("$d/conferences/conference/wwwdocs/photos/private","Do not copy\n");return $d;
}
sub create {attempt($^X,"$r/scripts/create-conference.pl",$_[0],'--admin-login','synthetic-admin')}
my $d=fixture('normal');my $before=read_text("$d/conferences/conference/actdocs/conf/act.ini");
my ($status,$out,$err)=create($d);is($status,0,'new edition setup completes') or diag($out.$err);
my $target="$d/conferences/winter2026";
my $config=read_text("$target/actdocs/conf/act.ini");
like($config,qr/^timezone = America\/Chicago$/m,'Austin timezone');
like($config,qr/^start_date = 2026-12-17 00:00:00$/m,'published start date');
like($config,qr/^end_date = 2026-12-18 23:59:59$/m,'two-day scheduling window');
like($config,qr/^full_uri = https:\/\/conference.perlcommunity.org\/winter2026\/$/m,'edition URL');
like($config,qr/^rooms = r1$/m,'one room');
like($config,qr/^type = NONE$/m,'old payment processor disabled');
like($config,qr/^show_schedule = 0$/m,'schedule not published prematurely');
like(read_text("$d/conf/act.ini"),qr/^conferences = conference older winter2026$/m,'existing edition list preserved and extended');
is(read_text("$d/conferences/conference/actdocs/conf/act.ini"),$before,'source edition config unchanged');
ok(-f "$target/actdocs/templates/local-wrapper",'local source wrappers preserved');
ok(!-e "$target/wwwdocs/photos/private",'private photos not copied');
like(read_text("$target/actdocs/static/index.html"),qr/December 17–18/,'edition-specific homepage');
ok(-f "$target/wwwdocs/images/pcc-oyster-156.webp",'shared theme assets copied');
is((stat("$target/actdocs/conf/act.ini"))[2]&0777,0640,'private configuration readable by ACT owner');
my $db=decode_json_text(read_text("$tmp/db-call.json"));
is_deeply([@$db[-2,-1]],['winter2026','synthetic-admin'],'database target and login passed as arguments');
my $sql=join ' ',@$db;
like($sql,qr/INSERT INTO rights/,'edition-specific administrator setup');
like($sql,qr/General Perl/,'default General Perl track');
like($sql,qr/Science Perl \/ Science Perl Journal/,'Science track');
unlike($sql,qr/UPDATE users|DELETE FROM|INSERT INTO talks/,'no shared-user changes, deletes, or copied proposals');
($status)=create($d);ok($status,'existing edition not overwritten');
my $stale=fixture('stale');{local $ENV{PCC_STALE}=1;($status)=create($stale)}ok($status,'mismatched running handler rejected');ok(!-e "$stale/conferences/winter2026",'stale-image failure creates no edition');
my $failed=fixture('dbfail');my $global_before=read_text("$failed/conf/act.ini");
{local $ENV{PCC_DB_FAIL}=1;($status)=create($failed)}ok($status,'database failure reported');ok(!-e "$failed/conferences/winter2026",'failed uncommitted edition files cleaned up');is(read_text("$failed/conf/act.ini"),$global_before,'failed edition not enabled');
my $ui=read_text("$r/theme/actdocs/templates/ui");like($ui,qr/global.config.general_full_uri/,'metadata derives from edition configuration');unlike($ui,qr{science.perlcommunity.org/conference/},'metadata is not tied to the old conference path');
like(read_text("$r/scripts/apply-theme.sh"),qr{editions/\$conf/index.html},'theme updates retain edition homepages');
done_testing;
