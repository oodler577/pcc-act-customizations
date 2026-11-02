package Pcc::Deploy;
use strict;
use warnings;
use Exporter 'import';
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Find;
use File::Path qw(make_path remove_tree);
use File::Temp qw(tempdir);
use IPC::Open3;
use IO::Select;
use IO::Handle;
use Symbol qw(gensym);
use Encode qw(decode);
use JSON::PP;
use POSIX qw(TCSAFLUSH ECHO);
our @EXPORT_OK=qw(read_text read_bytes write_text copy_file copy_tree backup_dir run attempt json decode_json_text conference_id deployment edit_section set_ini prompt compose root_required);
sub json { JSON::PP->new->canonical->pretty->allow_nonref->encode($_[0]) }
sub decode_json_text { JSON::PP->new->decode($_[0]) }
sub read_text { open my $f,'<:encoding(UTF-8)',$_[0] or die "Read $_[0]: $!\n"; local $/; return <$f> }
sub read_bytes { open my $f,'<:raw',$_[0] or die "Read $_[0]: $!\n"; local $/; return <$f> }
sub write_text {
 my ($path,$text)=@_; make_path(dirname($path)) unless -d dirname($path);
 open my $f,'>:encoding(UTF-8)',$path or die "Write $path: $!\n"; print $f $text or die "Write $path: $!\n"; close $f or die "Close $path: $!\n";
}
sub copy_file {
 my ($src,$dest)=@_; make_path(dirname($dest)) unless -d dirname($dest);
 copy($src,$dest) or die "Copy $src: $!\n"; chmod((stat($src))[2]&07777,$dest) or die "chmod $dest: $!\n";
}
sub copy_tree {
 my ($src,$dest)=@_;
 find({no_chdir=>1,wanted=>sub{
  my $path=$File::Find::name;my $rel=substr($path,length($src));my $to=$dest.$rel;
  die "Symlinks are not allowed in build sources: $path\n" if -l $path;
  if(-d $path){make_path($to)}elsif(-f $path){copy_file($path,$to)}
 }},$src);
}
sub backup_dir {
 my ($d,$prefix)=@_;make_path("$d/backups",{mode=>0700});
 return tempdir("$prefix-XXXXXXXX",DIR=>"$d/backups",CLEANUP=>0);
}
sub attempt {
 my @cmd=@_;my $err=gensym;my ($in,$out);
 my $pid=open3($in,$out,$err,@cmd);close $in;
 my $select=IO::Select->new($out,$err);my %buffers;my $outfd=fileno($out);my $errfd=fileno($err);
 while(my @ready=$select->can_read){
  for my $fh(@ready){my $fd=fileno($fh);my $n=sysread($fh,my $buf,65536);
   die "Read child output: $!\n" unless defined $n;
   if($n){$buffers{$fd}.=$buf}else{$select->remove($fh);close $fh}
  }
 }
 waitpid($pid,0);my $status=$?;
 return ($status,decode('UTF-8',$buffers{$outfd}//''),decode('UTF-8',$buffers{$errfd}//''));
}
sub run {
 my ($status,$out,$err)=attempt(@_);
 die "Command failed ($_[0]); private output suppressed\n" if $status;
 return $out;
}
sub compose { my $d=shift;return run('docker','compose','--project-directory',$d,@_) }
sub conference_id { die "Invalid conference ID\n" unless $_[0]=~/\A[A-Za-z0-9_-]+\z/;return $_[0] }
sub deployment { my $d=abs_path($_[0]);die "Deployment directory not found\n" unless $d && -d $d;return $d }
sub root_required { die "Run as root\n" if $> }
sub edit_section {
 my ($text,$name,$code,$create)=@_;
 if($text =~ /^(\[\Q$name\E\][^\S\n]*\n)(.*?)(?=^\[|\z)/msg){
  my ($begin,$end,$head,$body)=($-[0],$+[0],$1,$2);
  substr($text,$begin,$end-$begin,$head.$code->($body));
 }elsif($create){$text.="\n[$name]\n".$code->('')}else{die "Missing [$name] section; no changes made\n"}
 return $text;
}
sub set_ini {
 my ($body,$key,$value)=@_;my $count=()=$body=~/^[ \t]*\Q$key\E[ \t]*=/mg;
 die "Duplicate $key settings\n" if $count>1;
 if($count){$body=~s/^[ \t]*\Q$key\E[ \t]*=.*$/$key = $value/m}
 else{$body.="\n" unless $body eq '' || $body=~/\n\z/;$body.="$key = $value\n"}
 return $body;
}
sub prompt {
 my ($label,$hidden)=@_;
 open my $tty,'+<','/dev/tty' or die "An interactive terminal is required\n";
 binmode $tty,':encoding(UTF-8)';$tty->autoflush(1);print $tty $label;
 my ($term,$saved);
 if($hidden){$term=POSIX::Termios->new;$term->getattr(fileno($tty));$saved=$term->getlflag;$term->setlflag($saved & ~ECHO);$term->setattr(fileno($tty),TCSAFLUSH)}
 my $value;
 my $ok=eval {
  local $SIG{INT}=sub{die "Interrupted\n"};local $SIG{TERM}=sub{die "Interrupted\n"};
  $value=<$tty>;1;
 };my $error=$@;
 if($hidden){$term->setlflag($saved);$term->setattr(fileno($tty),TCSAFLUSH);print $tty "\n"}
 close $tty;die $error unless $ok;die "No input supplied\n" unless defined $value;
 $value=~s/\r?\n\z//;return $value;
}
1;
