#!/usr/bin/env perl
use strict;use warnings;
use FindBin;use lib "$FindBin::Bin/lib";
use Pcc::Deploy qw(read_text write_text copy_file copy_tree backup_dir run compose decode_json_text json conference_id deployment edit_section set_ini prompt root_required);
use Getopt::Long qw(GetOptions);
use Cwd qw(abs_path);
use File::Path qw(make_path remove_tree);
use Fcntl qw(O_WRONLY O_CREAT O_EXCL);
use JSON::PP;
my $conf='conference';GetOptions('conference=s'=>\$conf) or die "Invalid options\n";
my $d=deployment(shift // die "Usage: $0 DEPLOY SENDER [--conference ID]\n");
my $sender=shift // die "Sender required\n";die "Unexpected arguments\n" if @ARGV;
root_required();conference_id($conf);
die "Invalid sender\n" unless $sender=~/\A[A-Za-z0-9._%+-]+\@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\z/;
my $r=abs_path("$FindBin::Bin/..");
die "Deployment and secrets must be outside this repository\n" if $d eq $r || index($d,"$r/")==0;
die "Unset COMPOSE_FILE first\n" if $ENV{COMPOSE_FILE};
my @base=grep {-f "$d/$_"} qw(compose.yml compose.yaml docker-compose.yml docker-compose.yaml);
die "Expected exactly one base Compose file\n" unless @base==1;
for(qw(compose.override.yml compose.override.yaml docker-compose.override.yml docker-compose.override.yaml)){
 die "Existing Compose override requires manual merge; no changes made\n" if -e "$d/$_";
}
my $override="$d/".($base[0]=~/^docker-/ ? 'docker-compose.override.yml':'compose.override.yml');
my $config=decode_json_text(compose($d,'config','--format','json'));
my $image=$config->{services}{act}{image} // die "ACT image missing\n";
my $uid=compose($d,'exec','-T','act','id','-u');my $gid=compose($d,'exec','-T','act','id','-g');
for($uid,$gid){s/\s+\z//;die "Invalid container identity\n" unless /^\d+$/}
my @configs=("$d/conf/act.ini","$d/conferences/$conf/actdocs/conf/act.ini");
for(@configs){die "Missing configuration: $_\n" unless -f $_}
my $secret="$d/secrets/ses-smtp.json";
die "SMTP credential file already exists; stopping\n" if -e $secret;
die "SMTP build directory already exists; stopping\n" if -e "$d/smtp";
my $host=prompt('SES SMTP host [email-smtp.us-east-1.amazonaws.com]: ',0);
$host=~s/^\s+|\s+$//g;$host||='email-smtp.us-east-1.amazonaws.com';
die "Expected a standard SES SMTP hostname\n" unless $host=~/\Aemail-smtp\.[a-z0-9-]+\.amazonaws\.com\z/;
my $username=prompt('SES SMTP username: ',0);$username=~s/^\s+|\s+$//g;
my $password=prompt('SES SMTP password (hidden): ',1);
die "Passwords did not match\n" unless $password eq prompt('Confirm SMTP password: ',1);
die "Missing or invalid credentials\n" unless length($username) && length($password) && "$username$password"!~/[\r\n\x00]/;
umask 0077;my $backup=backup_dir($d,'smtp-before');
for my $f(@configs){my $rel=substr($f,length($d)+1);copy_file($f,"$backup/$rel")}
make_path("$d/secrets",{mode=>0700});
my $q=sub {JSON::PP->new->allow_nonref->encode($_[0])};
my $created_secret=0;
my $ok=eval{
 sysopen(my $fh,$secret,O_WRONLY|O_CREAT|O_EXCL,0600) or die "Create credential file: $!\n";
 $created_secret=1;
 binmode $fh,':encoding(UTF-8)';print $fh json({username=>$username,password=>$password});close $fh or die $!;
 chown $uid,$gid,$secret or die "Credential ownership: $!\n";
 copy_tree("$r/deploy/smtp","$d/smtp");
 for my $f(@configs){
  write_text($f,edit_section(read_text($f),'email',sub{
   my $body=shift;for my $pair(['sender_address',$sender],['test','0'],['hostname',$host],['port','587']){$body=set_ini($body,@$pair)}return $body;
  },1));
 }
 my $overlay="# Managed by PCC direct SMTP setup.\nservices:\n  act:\n    image: pcc-act-smtp:local\n    build:\n      context: ./smtp\n      args:\n        ACT_BASE_IMAGE: ".$q->($image)."\n    environment:\n      SMTP_HOST: ".$q->($host)."\n      SMTP_PORT: \"587\"\n      ACT_SMTP_FROM: ".$q->($sender)."\n      ACT_SMTP_FROM_NAME: \"Perl Community Conference\"\n      ACT_SMTP_CONFIG: /run/secrets/ses_smtp\n    secrets:\n      - ses_smtp\nsecrets:\n  ses_smtp:\n    file: ./secrets/ses-smtp.json\n";
 write_text($override,$overlay);compose($d,'config','--quiet');1;
};my $error=$@;
unless($ok){
 for my $f(@configs){my $rel=substr($f,length($d)+1);copy_file("$backup/$rel",$f)}
 unlink $override if -e $override;unlink $secret if $created_secret && -e $secret;remove_tree("$d/smtp");
 die $error;
}
print "SMTP credentials saved privately to: $secret\nConfiguration backup: $backup\n";
print "No containers changed and no mail sent.\n";
print "Next: docker compose --project-directory $d build act\n";
print "Then: docker compose --project-directory $d up -d --no-deps --force-recreate act\n";
