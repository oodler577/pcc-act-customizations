#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/lib";
use Pcc::Deploy qw(read_text read_bytes write_text copy_file backup_dir attempt decode_json_text conference_id deployment edit_section set_ini);
use Getopt::Long qw(GetOptions);
use Digest::SHA qw(sha256_hex);
my ($conf,$activate,$single_room)=('conference',0,0);
GetOptions('conference=s'=>\$conf,'activate'=>\$activate,'single-room'=>\$single_room) or die "Invalid options\n";
my $d=deployment(shift // die "Usage: $0 DEPLOY [--conference ID] [--activate] [--single-room]\n");
die "Unexpected arguments\n" if @ARGV;conference_id($conf);die "--single-room is a staging option, not an activation option\n" if $single_room && $activate;
umask 0077;
my $r="$FindBin::Bin/..";my $ini="$d/conferences/$conf/actdocs/conf/act.ini";
die "Expected existing PCC deployment with SMTP image\n" unless -f $ini && -f "$d/smtp/Dockerfile";
my $backup=backup_dir($d,'proposals-before');
if($activate){
 die "Run staging and build the image first\n" unless -f "$d/smtp/lib/Pcc/Proposal.pm";
 my @paths=('Pcc/Proposal.pm','Act/Handler/Talk/Edit.pm');
 my ($status,$out)=attempt('docker','compose','--project-directory',$d,'exec','-T','act','perl','-MDigest::SHA=sha256_hex','-e',
  'local $/; for (@ARGV) { open my $f, "<", $_ or die $!; print sha256_hex(<$f>), "\n"; }',
  map {"/opt/act/lib/$_"} @paths);
 my $expected=join '',map {sha256_hex(read_bytes("$r/deploy/smtp/lib/$_"))."\n"} @paths;
 die "Running ACT image does not contain this proposal code. Build and recreate act before activation.\n" unless !$status && $out eq $expected;
 my $dest="$d/conferences/$conf/actdocs/templates/talk/add";
 copy_file($dest,"$backup/talk-add") if -f $dest;
 copy_file("$r/theme/actdocs/templates/talk/add",$dest);chmod 0644,$dest or die $!;
 write_text("$d/.pcc-proposals-enabled",'');chmod 0600,"$d/.pcc-proposals-enabled" or die $!;
 print "Form activated. Apply the theme to refresh styles and restart act.\n";
}else{
 my $updated=edit_section(read_text($ini),'talks',sub{set_ini($_[0],'durations','30 55')});
 if($single_room){
  my $first;
  $updated=edit_section($updated,'rooms',sub{
   my $body=shift;
   ($first)=$body=~/^[ \t]*rooms[ \t]*=[ \t]*([A-Za-z0-9_-]+)/m;
   die "No configured room code; stopping\n" unless $first;
   return set_ini(set_ini($body,'rooms',$first),$first.'_name_en','Main program');
  });
  # Check both talk and event assignments before hiding additional rooms.
  my ($status,$out)=attempt('docker','compose','--project-directory',$d,'exec','-T','act',
    'perl','-Ilib','-MAct::Config','-MAct::Store::Database','-MJSON::PP','-e',
    'my $dbh=Act::Store::Database->instance->dbh; my $rows=$dbh->selectcol_arrayref(q{SELECT DISTINCT room FROM talks WHERE conf_id=? AND room IS NOT NULL UNION SELECT DISTINCT room FROM events WHERE conf_id=? AND room IS NOT NULL},undef,$ARGV[0],$ARGV[0]); print JSON::PP->new->encode($rows);',
    $conf);
  die "Cannot check existing room assignments; no configuration changes made\n" if $status;
  my $used=decode_json_text($out);my @other=grep {defined($_) && length($_) && $_ ne $first} @$used;
  die "Other rooms still have assigned talks/events: ".join(', ',@other).". No configuration changes made.\n" if @other;
  print "Single main-program room configured: $first. Existing assignments are unchanged.\n";
 }
 copy_file($ini,"$backup/act.ini");
 for my $rel('Pcc/Proposal.pm','Act/Handler/Talk/Edit.pm'){
  my $dest="$d/smtp/lib/$rel";copy_file($dest,"$backup/lib/$rel") if -f $dest;
  copy_file("$r/deploy/smtp/lib/$rel",$dest);
 }
 write_text($ini,$updated);
 print "Staged proposal handler and 30/55-minute choices. No database changes.\n";
}
print "Backup: $backup\n";
