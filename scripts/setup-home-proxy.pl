#!/usr/bin/env perl
use strict;use warnings;
use FindBin;use lib "$FindBin::Bin/lib";
use Pcc::Deploy qw(read_text write_text copy_file backup_dir attempt compose deployment edit_section set_ini root_required);
use Pcc::HomeProxy qw(home_proxy_config);
use Getopt::Long qw(GetOptions);
my $host='conference.perlcommunity.org';
GetOptions('host=s'=>\$host) or die "Invalid options\n";
my $proxy=deployment(shift // die "Usage: $0 PROXY_DIRECTORY ACT_DEPLOY_DIRECTORY\n");
my $act=deployment(shift // die "ACT deployment directory required\n");
die "Unexpected arguments\n" if @ARGV;root_required();umask 0077;
my $nginx="$proxy/nginx.conf";my $ini="$act/conferences/conference/actdocs/conf/act.ini";
die "Expected existing Nginx and ACT conference config\n" unless -f $nginx && -f $ini;
my $old_nginx=read_text($nginx);my $old_ini=read_text($ini);
my $new_nginx=home_proxy_config($old_nginx,$host);
my $new_ini=edit_section($old_ini,'general',sub{set_ini($_[0],'full_uri',"https://$host/")});
my $backup=backup_dir($proxy,'root-home-before');
copy_file($nginx,"$backup/nginx.conf");copy_file($ini,"$backup/conference-act.ini");
print "Backup: $backup\n";
my $ok=eval {
 write_text($nginx,$new_nginx);
 compose($proxy,'exec','-T','nginx','nginx','-t');
 write_text($ini,$new_ini);
 compose($act,'restart','act');
 compose($proxy,'exec','-T','nginx','nginx','-s','reload');
 1;
};my $error=$@;
unless($ok){
 write_text($nginx,$old_nginx);write_text($ini,$old_ini);
 my ($act_status)=attempt('docker','compose','--project-directory',$act,'restart','act');
 my ($nginx_status)=attempt('docker','compose','--project-directory',$proxy,'exec','-T','nginx','nginx','-s','reload');
 print STDERR "Original files restored. Check service status; automatic recovery command failed.\n" if $act_status || $nginx_status;
 die $error;
}
print "Home: https://$host/\nLegacy conference home URLs now redirect to root.\n";
print "Edition and account routes are preserved on the conference hostname. Science ACT URLs redirect; OJS stays on science.\n";
