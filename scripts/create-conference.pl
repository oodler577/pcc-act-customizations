#!/usr/bin/env perl
use strict;use warnings;
use FindBin;use lib "$FindBin::Bin/lib";
use Pcc::Deploy qw(read_text read_bytes write_text copy_file copy_tree backup_dir run attempt compose json decode_json_text conference_id deployment edit_section set_ini root_required);
use Getopt::Long qw(GetOptions);
use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path remove_tree);
use File::Find;
use File::Basename qw(basename);
my ($edition,$source,$admin)=('winter2026','conference',undef);
GetOptions('edition=s'=>\$edition,'from=s'=>\$source,'admin-login=s'=>\$admin) or die "Invalid options\n";
my $d=deployment(shift // die "Usage: $0 DEPLOY --admin-login LOGIN [--edition winter2026] [--from conference]\n");
die "Unexpected arguments\n" if @ARGV;root_required();conference_id($edition);conference_id($source);
die "Provide an existing administrator login\n" unless defined($admin) && $admin =~ /\S/ && $admin !~ /[\r\n\x00]/;
die "Source and target must differ\n" if $edition eq $source;
umask 0077;
my $r="$FindBin::Bin/..";
my $profile_path="$r/editions/$edition/config.json";
die "No reviewed edition profile for $edition\n" unless -f $profile_path && -f "$r/editions/$edition/index.html";
my $profile=decode_json_text(read_text($profile_path));
die "Invalid edition profile\n" unless $profile->{id} eq $edition && $profile->{timezone} eq 'America/Chicago' && $profile->{full_uri} =~ m{\Ahttps://conference\.perlcommunity\.org/\Q$edition\E/\z};
my $global="$d/conf/act.ini";my $source_dir="$d/conferences/$source";my $target="$d/conferences/$edition";
die "Missing source/global configuration\n" unless -f $global && -f "$source_dir/actdocs/conf/act.ini";
die "Edition directory already exists; no changes made\n" if -e $target;
compose($d,'config','--quiet');
# The new form must never be installed over a different handler version.
my @modules=('Pcc/Proposal.pm','Act/Handler/Talk/Edit.pm');
my ($status,$hashes)=attempt('docker','compose','--project-directory',$d,'exec','-T','act','perl','-MDigest::SHA=sha256_hex','-e',
 'local $/; for (@ARGV) { open my $f,"<",$_ or die $!; print sha256_hex(<$f>),"\n"; }',map {"/opt/act/lib/$_"} @modules);
my $expected=join '',map {sha256_hex(read_bytes("$r/deploy/smtp/lib/$_"))."\n"} @modules;
die "Build and recreate ACT using this checkout's proposal code first\n" if $status || $hashes ne $expected;
my $uid=compose($d,'exec','-T','act','id','-u');my $gid=compose($d,'exec','-T','act','id','-g');
for($uid,$gid){s/\s+\z//;die "Invalid ACT identity\n" unless /^\d+$/}
my $old_global=read_text($global);
my $new_global=edit_section($old_global,'general',sub{
 my $body=shift;my ($list)=$body=~/^[ \t]*conferences[ \t]*=[ \t]*([^\n]*)/m;
 die "Missing conferences list\n" unless defined $list;
 $list =~ s/\s*[#;].*//;my @ids=split /\s+/,$list;
 die "Target conference already enabled\n" if grep {$_ eq $edition} @ids;
 die "Source conference not enabled\n" unless grep {$_ eq $source} @ids;
 return set_ini($body,'conferences',join(' ',@ids,$edition));
});
my $conf=read_text("$source_dir/actdocs/conf/act.ini");
$conf=edit_section($conf,'general',sub{
 my $body=shift;
 for my $pair(['name_en',$profile->{title}],['full_uri',$profile->{full_uri}],['timezone',$profile->{timezone}],['languages','en'],['default_language','en'],['default_country','us']){$body=set_ini($body,@$pair)}return $body;
});
$conf=edit_section($conf,'registration',sub{set_ini($_[0],'open','1')},1);
$conf=edit_section($conf,'talks',sub{
 my $body=shift;for my $pair(['start_date',$profile->{start_date}],['end_date',$profile->{end_date}],['submissions_open','1'],['edition_open','1'],['show_schedule','0'],['durations','30 55']){$body=set_ini($body,@$pair)}return $body;
});
$conf=edit_section($conf,'rooms',sub{my $body=set_ini($_[0],'rooms','r1');return set_ini($body,'r1_name_en','Main program')},1);
# No unconfigured payment processor or old event's product prices are enabled.
$conf=edit_section($conf,'payment',sub{my $body=set_ini($_[0],'open','0');return set_ini($body,'type','NONE')},1);
my $backup=backup_dir($d,"before-$edition");copy_file($global,"$backup/global-act.ini");
print "Configuration backup: $backup\n";
my $db_script=<<'DB';
use strict;use warnings;use Act::Config;use Act::Store::Database;use JSON::PP;
my ($edition,$login)=@ARGV;my $dbh=Act::Store::Database->instance->dbh;
my ($id)=$dbh->selectrow_array('SELECT user_id FROM users WHERE login=?',undef,$login);
die "Administrator login does not exist\n" unless defined $id;
$dbh->begin_work;
eval {
 for my $table(qw(participations rights tracks talks events invoice_num)){
  my ($count)=$dbh->selectrow_array("SELECT COUNT(*) FROM $table WHERE conf_id=?",undef,$edition);
  die "Target conference already has database records; stopping\n" if $count;
 }
 $dbh->do('INSERT INTO participations (conf_id,user_id,datetime) VALUES (?,?,CURRENT_TIMESTAMP)',undef,$edition,$id);
 for my $right(qw(admin talks_admin users_admin news_admin wiki_admin treasurer)){
  $dbh->do('INSERT INTO rights (right_id,conf_id,user_id) VALUES (?,?,?)',undef,$right,$edition,$id);
 }
 $dbh->do('INSERT INTO invoice_num (conf_id,next_num) VALUES (?,1)',undef,$edition);
 for my $track(['General Perl','Perl 5 projects, tools, applications, and practical experience.'],['Science Perl / Science Perl Journal','Scientific research and paper-based presentations; journal review is separate.']){
  $dbh->do('INSERT INTO tracks (conf_id,title,description) VALUES (?,?,?)',undef,$edition,@$track);
 }
 $dbh->commit;1;
} or do {my $error=$@;$dbh->rollback;die $error};
print "Edition administrator and default tracks created. No existing participation or proposals copied.\n";
DB
my $db_committed=0;
my $ok=eval{
 mkdir($target,0755) or die "Create edition directory: $!\n";
 # Keep only theme/configuration inputs; never clone uploads or database records.
 copy_tree("$source_dir/actdocs/templates","$target/actdocs/templates") if -d "$source_dir/actdocs/templates";
 copy_tree("$r/theme/actdocs/templates","$target/actdocs/templates");
 copy_tree("$r/theme/actdocs/static","$target/actdocs/static");
 copy_tree("$r/theme/wwwdocs","$target/wwwdocs");
 for my $page (glob "$r/editions/$edition/*.html") {
  next unless -f $page;
  copy_file($page,"$target/actdocs/static/".basename($page));
 }
 write_text("$target/actdocs/conf/act.ini",$conf);
 find({no_chdir=>1,wanted=>sub{my $file=$File::Find::name;die "Unexpected symlink\n" if -l $file;chmod(-d $file?0755:0644,$file) or die "chmod: $!\n";chown($uid,$gid,$file) or die "chown: $!\n"}},$target);
 chmod 0640,"$target/actdocs/conf/act.ini" or die $!;
 my ($code,$out)=attempt('docker','compose','--project-directory',$d,'exec','-T','act','perl','-Ilib','-e',$db_script,$edition,$admin);
 die "Database setup failed; no configuration enabled. Check administrator login and whether this edition already exists.\n" if $code;
 $db_committed=1;print $out;
 write_text($global,$new_global);
 write_text("$d/.pcc-proposals-enabled",'');chmod 0600,"$d/.pcc-proposals-enabled" or die $!;
 compose($d,'restart','act');1;
};my $error=$@;
unless($ok){
 if(!$db_committed){remove_tree($target) if -d $target}
 else{print STDERR "Edition files/database were prepared. Keep them for recovery. Global backup: $backup/global-act.ini\n"}
 die $error;
}
my $ready=0;
for(1..20){
 my ($code,$out)=attempt('curl','--silent','--show-error','--max-time','2','--output','/dev/null','--write-out','%{http_code}',"http://127.0.0.1:5000/$edition/");
 if(!$code && $out eq '200'){$ready=1;last}select undef,undef,undef,.5;
}
die "Edition enabled but local HTTP check did not return 200. Check ACT logs and the conferences bind mount.\n" unless $ready;
print "Ready: $profile->{full_uri}\nScheduling window: $profile->{start_date} through $profile->{end_date}; time zone: $profile->{timezone}\n";
print "Existing accounts are shared. Only the named administrator was registered for this edition.\n";
print "Apply the theme to the source landing page to show the Winter 2026 links.\n";
