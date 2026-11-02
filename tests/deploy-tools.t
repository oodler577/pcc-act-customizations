use strict;use warnings;
use Test::More;
use FindBin;use lib "$FindBin::Bin/../scripts/lib";
use Pcc::Deploy qw(read_text read_bytes write_text run attempt json decode_json_text);
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
my $r=abs_path("$FindBin::Bin/..");
my $tmp=tempdir(CLEANUP=>1);my $d="$tmp/deploy";make_path("$d/conf","$d/conferences/conference/actdocs/conf","$tmp/bin");
local $ENV{PATH}="$tmp/bin:$ENV{PATH}";
local $ENV{PCC_TEST_REPO}=$r;
local $ENV{COMPOSE_FILE};delete $ENV{COMPOSE_FILE};
write_text("$tmp/bin/docker",<<'DOCKER');
#!/usr/bin/env perl
use strict;use warnings;use JSON::PP;use Digest::SHA;
my $cmd=join ' ',@ARGV;
if($cmd=~/config --format json/){print encode_json({services=>{act=>{image=>'synthetic-base',build=>{args=>{ACT_BASE_IMAGE=>'synthetic-base'}}}}})}
elsif($cmd=~/config --quiet/){exit($ENV{PCC_FAIL_CONFIG}?1:0)}
elsif($cmd=~/id -[ug]/){print "10001\n"}
elsif($cmd=~/SELECT DISTINCT room/){print encode_json($ENV{PCC_BUSY_ROOM}?['r2']:[])}
elsif($cmd=~/exec/){
 exit 1 if $ENV{PCC_STALE_IMAGE};
 for my $rel('Pcc/Proposal.pm','Act/Handler/Talk/Edit.pm'){
  open my $f,'<:raw',"$ENV{PCC_TEST_REPO}/deploy/smtp/lib/$rel" or die $!;
  my $sha=Digest::SHA->new(256);$sha->addfile($f);print $sha->hexdigest,"\n";
 }
}
elsif($cmd=~/ps -q/){print "synthetic-container\n"}
elsif($cmd=~/^inspect /){print encode_json([{Image=>'sha256:synthetic',Config=>{Env=>['SECRET=must-not-escape'],Labels=>{'com.docker.compose.service'=>'act'}}}])}
elsif($cmd=~/^image inspect/){print encode_json([{Id=>'sha256:synthetic',RepoDigests=>['synthetic@sha256:fake'],Os=>'linux',Architecture=>'amd64',Size=>123}])}
elsif($cmd=~/^image save/){binmode STDOUT;print "synthetic image stream\0\n"}
else{die "Unexpected mock Docker command\n"}
DOCKER
chmod 0755,"$tmp/bin/docker";
my $ini="$d/conferences/conference/actdocs/conf/act.ini";
my $original="[general]\nname_en = Old name\nlanguages = en nl\ndefault_language = nl\n[talks]\ndurations = 20 40\n[other]\nvalue = keep\n";
write_text($ini,$original);write_text("$d/conf/act.ini","[database]\npasswd = synthetic-private-config\n");
write_text("$d/compose.yml","services: {}\n");
sub invoke { attempt($^X,"$r/scripts/$_[0]",$d,@_[1..$#_]) }
sub status_ok { my ($status,$out,$err)=@_;is($status,0,$out||$err) }
# SMTP installation is root-only. Replace terminal input inside a subprocess,
# retaining the actual script, file operations and Docker validation.
SKIP: {
 skip 'SMTP installation needs root ownership operations',16 if $>;
 write_text("$tmp/mail-wrapper.pl",<<'WRAPPER');
use strict;use warnings;
use FindBin;
BEGIN { $FindBin::Bin=$ENV{PCC_TEST_REPO}.'/scripts' }
use lib $ENV{PCC_TEST_REPO}.'/scripts/lib';
use Pcc::Deploy;
no warnings 'redefine';
my @answers=('email-smtp.us-east-1.amazonaws.com','synthetic-user','synthetic-password','synthetic-password');
*Pcc::Deploy::prompt=sub { shift @answers };
do "$FindBin::Bin/setup-mail.pl" or die $@;
WRAPPER
 my ($status,$out,$err)=attempt($^X,"$tmp/mail-wrapper.pl",$d,'sender@example.invalid');
 is($status,0,'Perl SMTP installation succeeds');
 unlike($out.$err,qr/synthetic-password/,'setup does not print password');
 my $secret="$d/secrets/ses-smtp.json";
 ok(-f $secret,'private credential file created');
 is((stat($secret))[2]&0777,0600,'credential file mode 0600');
 is((stat($secret))[4],10001,'credential file uses ACT UID');
 is(decode_json_text(read_text($secret))->{username},'synthetic-user','credentials saved correctly');
 like(read_text("$d/compose.override.yml"),qr/SMTP_PORT: "587"/,'STARTTLS port staged');
 like(read_text($ini),qr/hostname = email-smtp/,'mail configuration staged');
 ok(-f "$d/smtp/lib/Pcc/SMTP.pm",'Perl SMTP adapter staged');
 ($status,$out,$err)=attempt($^X,"$tmp/mail-wrapper.pl",$d,'sender@example.invalid');
 ok($status,'repeated SMTP installation refuses to overwrite existing setup');
 my $bad="$tmp/rollback";make_path("$bad/conf","$bad/conferences/conference/actdocs/conf");
 write_text("$bad/compose.yml","services: {}\n");
 write_text("$bad/conf/act.ini","[email]\nhostname = old-mail\n");
 write_text("$bad/conferences/conference/actdocs/conf/act.ini",$original);
 {
  local $ENV{PCC_FAIL_CONFIG}=1;
  ($status,$out,$err)=attempt($^X,"$tmp/mail-wrapper.pl",$bad,'sender@example.invalid');
 }
 ok($status,'SMTP Compose validation failure is reported');
 is(read_text("$bad/conf/act.ini"),"[email]\nhostname = old-mail\n",'SMTP failure restores global config');
 is(read_text("$bad/conferences/conference/actdocs/conf/act.ini"),$original,'SMTP failure restores conference config');
 ok(!-e "$bad/secrets/ses-smtp.json",'SMTP failure removes new credential file');
 ok(!-e "$bad/compose.override.yml",'SMTP failure removes new override');
 ok(!-e "$bad/smtp",'SMTP failure removes new build context');

}
# Set up the minimum derivative build if the root-only block was skipped.
make_path("$d/smtp");write_text("$d/smtp/Dockerfile","FROM synthetic\n") unless -f "$d/smtp/Dockerfile";
write_text("$d/compose.override.yml","services:\n  act:\n    environment:\n      ACT_SMTP_FROM: sender\n") unless -f "$d/compose.override.yml";
status_ok(invoke('setup-proposals.pl'));
like(read_text($ini),qr/durations = 30 55/,'proposal durations updated');
like(read_text($ini),qr/\[other\]\nvalue = keep/,'unrelated config preserved');
ok(-f "$d/smtp/lib/Pcc/Proposal.pm",'proposal module staged');
{local $ENV{PCC_STALE_IMAGE}=1;my ($status)=invoke('setup-proposals.pl','--activate');ok($status,'stale image rejected');ok(!-e "$d/.pcc-proposals-enabled",'failed activation does not mark enabled')}
status_ok(invoke('setup-proposals.pl','--activate'));
ok(-f "$d/.pcc-proposals-enabled",'matching running image activates form');
ok(-f "$d/conferences/conference/actdocs/templates/talk/add",'new template installed');
status_ok(invoke('update-site.pl'));
like(read_text($ini),qr/^languages = en$/m,'English-only languages');
like(read_text($ini),qr/^default_language = en$/m,'English default');
ok(-f "$d/smtp/lib/Act/Handler/Wiki.pm",'wiki override staged');
SKIP: {
 skip 'Branding helper requires root',3 if $>;
 status_ok(invoke('set-conference-branding.pl','--name','Updated PCC'));
 like(read_text($ini),qr/name_en = Updated PCC/,'conference name updated');
 like(read_text("$d/compose.override.yml"),qr/ACT_SMTP_FROM_NAME: "Updated PCC"/,'SMTP display name updated');
}
write_text($ini,read_text($ini)."\n[rooms]\nrooms = r1 r2 r3\nr1_name_en = Room 1\nr2_name_en = Room 2\nr3_name_en = Room 3\n");
my $before_rooms=read_text($ini);
{
 local $ENV{PCC_BUSY_ROOM}=1;
 my ($blocked)=invoke('setup-proposals.pl','--single-room');
 ok($blocked,'single-room conversion refuses other assigned rooms');
 is(read_text($ini),$before_rooms,'busy-room refusal leaves configuration unchanged');
}
status_ok(invoke('setup-proposals.pl','--single-room'));
like(read_text($ini),qr/^rooms = r1$/m,'only first room remains active');
like(read_text($ini),qr/^r1_name_en = Main program$/m,'single room labeled Main program');
my ($status,$out,$err)=invoke('checkpoint-images.pl','--output',"$tmp/checkpoint",'--archive');
is($status,0,'Perl checkpoint completes');
my $manifest=read_text("$tmp/checkpoint/images.json");
unlike($manifest,qr/must-not-escape|synthetic-private-config/,'checkpoint whitelists image metadata');
is(decode_json_text($manifest)->{services}{act}{image_id},'sha256:synthetic','exact runtime ID captured');
my $archive=read_bytes("$tmp/checkpoint/images.tar.gz");
like(read_text("$tmp/checkpoint/images.tar.gz.sha256"),qr/\Q@{[sha256_hex($archive)]}\E/,'image archive checksum matches');
my $uncompressed;gunzip("$tmp/checkpoint/images.tar.gz"=>\$uncompressed) or die $GunzipError;
is($uncompressed,"synthetic image stream\0\n",'binary image stream preserved');
done_testing;
