#!/usr/bin/env perl
use strict;use warnings;
use FindBin;use lib "$FindBin::Bin/lib";
use Pcc::Deploy qw(write_text read_text run attempt compose json decode_json_text deployment);
use Getopt::Long qw(GetOptions);
use File::Path qw(make_path);
use File::Basename qw(dirname);
use IO::Compress::Gzip qw($GzipError);
use Digest::SHA;
use POSIX qw(strftime);
my ($output,$archive);
GetOptions('output=s'=>\$output,'archive'=>\$archive) or die "Invalid options\n";
my $d=deployment(shift // die "Usage: $0 DEPLOY [--output NEW_DIRECTORY] [--archive]\n");
die "Unexpected arguments\n" if @ARGV;umask 0077;
my $config=decode_json_text(compose($d,'config','--format','json'));
my @containers=split /\s+/,compose($d,'ps','-q');die "No running Compose containers\n" unless @containers;
my (%images,%services,%bases);
sub record_image {
 my ($image)=@_;my $id=$image->{Id};
 $images{$id}={repo_digests=>$image->{RepoDigests}||[],platform=>($image->{Os}//'').'/'.($image->{Architecture}//''),size_bytes=>$image->{Size}//0};
 return $id;
}
for my $cid(@containers){
 my $container=decode_json_text(run('docker','inspect',$cid))->[0];
 my $service=$container->{Config}{Labels}{'com.docker.compose.service'};
 my $image=decode_json_text(run('docker','image','inspect',$container->{Image}))->[0];
 $services{$service}={image_id=>record_image($image)};
}
my @missing=grep {!exists $services{$_}} sort keys %{$config->{services}};
for my $service(sort keys %{$config->{services}}){
 my $build=$config->{services}{$service}{build}||{};
 my $base=($build->{args}||{})->{ACT_BASE_IMAGE};next unless $base;
 my ($status,$out)=attempt('docker','image','inspect',$base);next if $status;
 $bases{$service}=record_image(decode_json_text($out)->[0]);
}
my $stamp=strftime('%Y%m%d-%H%M%S',gmtime)."-$$";
$output //= "$d/backups/images-$stamp";die "Checkpoint directory already exists\n" if -e $output;
make_path(dirname($output),{mode=>0700});mkdir($output,0700) or die "Create checkpoint: $!\n";
my $revision=run('git','-C',"$FindBin::Bin/..",'rev-parse','HEAD');chomp $revision;
write_text("$output/images.json",json({format=>1,created_utc=>$stamp,services=>\%services,build_base_images=>\%bases,images=>\%images,services_not_running=>\@missing,customization_commit=>$revision}));
write_text("$output/images.lock.json",json({services=>{map {$_=>{image=>$services{$_}{image_id},pull_policy=>'never'}} keys %services}}));
if($archive){
 my $partial="$output/images.tar.gz.partial";
 my $ok=eval{
  open my $pipe,'-|','docker','image','save',sort keys %images or die "Start docker image save: $!\n";
  binmode $pipe;
  my $gzip=IO::Compress::Gzip->new($partial,Level=>1) or die "Create archive: $GzipError\n";
  while(1){my $n=read($pipe,my $buf,1024*1024);die "Read image stream: $!\n" unless defined $n;last unless $n;$gzip->print($buf) or die "Write archive: $GzipError\n"}
  close $pipe or die "docker image save failed\n";$gzip->close or die "Close archive: $GzipError\n";
  rename($partial,"$output/images.tar.gz") or die "Finalize archive: $!\n";
  open my $fh,'<:raw',"$output/images.tar.gz" or die $!;
  my $sha=Digest::SHA->new(256);$sha->addfile($fh);close $fh;
  write_text("$output/images.tar.gz.sha256",$sha->hexdigest."  images.tar.gz\n");1;
 };my $error=$@;unless($ok){unlink $partial if -e $partial;die $error}
}
print "Image checkpoint: $output\nRunning services: ",join(', ',sort keys %services),"\n";
print "Not captured (not running): ",join(', ',@missing),"\n" if @missing;
print "Images only. Back up database volumes, configuration, secrets and conference files separately.\n";
print "No image archive saved. Use --archive to recover deleted images.\n" unless $archive;
