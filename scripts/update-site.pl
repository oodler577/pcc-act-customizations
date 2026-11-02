#!/usr/bin/env perl
use strict;use warnings;
use FindBin;use lib "$FindBin::Bin/lib";
use Pcc::Deploy qw(read_text write_text copy_file backup_dir conference_id deployment edit_section set_ini);
use Getopt::Long qw(GetOptions);
my $conf='conference';GetOptions('conference=s'=>\$conf) or die "Invalid options\n";
my $d=deployment(shift // die "Usage: $0 DEPLOY [--conference ID]\n");
die "Unexpected arguments\n" if @ARGV;conference_id($conf);umask 0077;
my $r="$FindBin::Bin/..";my $ini="$d/conferences/$conf/actdocs/conf/act.ini";
die "Expected existing PCC deployment with SMTP image\n" unless -f $ini && -f "$d/smtp/Dockerfile";
my $updated=edit_section(read_text($ini),'general',sub{
 my $body=set_ini($_[0],'languages','en');return set_ini($body,'default_language','en');
});
my $backup=backup_dir($d,'site-before');copy_file($ini,"$backup/act.ini");
for my $rel('Act/Handler/Wiki.pm','Act/Handler/WikiEdit.pm','Act/Middleware/Language.pm'){
 my $dest="$d/smtp/lib/$rel";copy_file($dest,"$backup/lib/$rel") if -f $dest;
 copy_file("$r/deploy/smtp/lib/$rel",$dest);
}
write_text($ini,$updated);
print "Staged site changes. Configuration backup: $backup\n";
print "Next: apply-theme.sh, then docker compose build act and recreate act.\n";
