#!/usr/bin/env perl
use strict;use warnings;
use FindBin;use lib "$FindBin::Bin/lib";
use Pcc::Deploy qw(read_text write_text copy_file copy_tree backup_dir conference_id deployment edit_section set_ini root_required);
use Getopt::Long qw(GetOptions);
use JSON::PP;
my ($conf,$name)=('conference','Perl Community Conference');
GetOptions('conference=s'=>\$conf,'name=s'=>\$name) or die "Invalid options\n";
my $d=deployment(shift // die "Usage: $0 DEPLOY [--name NAME] [--conference ID]\n");
die "Unexpected arguments\n" if @ARGV;root_required();conference_id($conf);
die "Invalid display name\n" unless $name=~/\S/ && $name!~/[\r\n\x00]/;
umask 0077;my $r="$FindBin::Bin/..";my $ini="$d/conferences/$conf/actdocs/conf/act.ini";
my @overrides=grep {-f $_} map {"$d/$_"} qw(compose.override.yml compose.override.yaml docker-compose.override.yml docker-compose.override.yaml);
die "Expected installed direct SMTP setup\n" unless @overrides==1 && -f $ini && -d "$d/smtp";
my $override=$overrides[0];
my $updated=edit_section(read_text($ini),'general',sub{
 my $body=shift;$body=~s/^(name(?:_[A-Za-z_]+)?)[ \t]*=.*$/$1 = $name/mg;
 return set_ini($body,'name_en',$name);
});
my $overlay=read_text($override);
my $setting='      ACT_SMTP_FROM_NAME: '.JSON::PP->new->allow_nonref->encode($name);
if($overlay=~/^      ACT_SMTP_FROM_NAME:/m){$overlay=~s/^      ACT_SMTP_FROM_NAME:.*$/$setting/m}
else{my $n=$overlay=~s/^(      ACT_SMTP_FROM:.*)$/$1\n$setting/mg;die "Unrecognized SMTP override; no changes made\n" unless $n==1}
my $backup=backup_dir($d,'branding-before');
for my $f($ini,$override){my $rel=substr($f,length($d)+1);copy_file($f,"$backup/$rel")}
write_text($ini,$updated);write_text($override,$overlay);
copy_tree("$r/deploy/smtp","$d/smtp");
print "Conference name and SMTP sender name: $name\nConfiguration backup: $backup\n";
print "SMTP credentials were not read or changed.\nRebuild Act, recreate its container, then apply the theme as documented.\n";
