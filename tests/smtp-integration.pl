#!/usr/bin/env perl
use strict;use warnings;
use FindBin;use lib "$FindBin::Bin/../scripts/lib";
use Pcc::Deploy qw(read_text read_bytes write_text run attempt json decode_json_text root_required);
use Getopt::Long qw(GetOptions);
use File::Temp qw(tempdir);
use File::Path qw(remove_tree);
use IO::Socket::INET;
use IO::Socket::SSL;
use MIME::Base64 qw(decode_base64 encode_base64);
use Test::More;
use POSIX qw(WNOHANG);
root_required();
my $image='pcc-act-smtp-integration';GetOptions('image=s'=>\$image) or die "Invalid options\n";
my $d=tempdir('pcc-direct-smtp-test-XXXXXXXX',TMPDIR=>1,CLEANUP=>0);
my $server;my $owner=$$;
END { my $status=$?; if($$==$owner){if($server){kill 'TERM',$server;waitpid($server,0)} remove_tree($d) if $d && -d $d} $?=$status }
run('openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=smtp.integration.test','-addext','subjectAltName=DNS:smtp.integration.test','-keyout',"$d/key.pem",'-out',"$d/cert.pem");
write_text("$d/ca.pem",read_text('/etc/ssl/certs/ca-certificates.crt').read_text("$d/cert.pem"));
my $gateway=decode_json_text(run('docker','network','inspect','bridge'))->[0]{IPAM}{Config}[0]{Gateway};
write_text("$d/send.pl",<<'SENDER');
use strict;use warnings;use Pcc::SMTP;use Email::Simple;
my $smtp=Pcc::SMTP->new(config_file=>'/run/secrets/ses_smtp');
my $email=Email::Simple->create(header=>[
 From=>'sender@example.invalid',To=>'"Primary Person" <recipient@example.invalid>',
 Cc=>'copy@example.invalid',Bcc=>'hidden@example.invalid, recipient@example.invalid',
 Subject=>'Synthetic direct SMTP test','Content-Type'=>'text/plain; charset=UTF-8',
],body=>"Synthetic direct SMTP body.\r\n");
$smtp->send($email);
die "Original Bcc changed" unless $email->header('Bcc');
print "SMTP submission accepted\n";
SENDER
chmod 0644,"$d/ca.pem","$d/send.pl";
$server=fork();die "fork: $!\n" unless defined $server;
if(!$server){
 $server=undef;
 # This deliberately small SMTP sink is only for isolated TLS/AUTH tests.
 my $listener=IO::Socket::INET->new(LocalAddr=>$gateway,LocalPort=>587,Listen=>5,ReuseAddr=>1) or die "Test SMTP bind: $!\n";
 write_text("$d/ready",'ready');
 while(my $client=$listener->accept){
  $client->autoflush(1);print $client "220 smtp.integration.test ESMTP\r\n";
  my ($tls,$auth,$sender,@recips)=(0,0,'');
  eval {
   while(my $line=<$client>){
    $line=~s/\r?\n\z//;
    if($line=~/^(?:EHLO|HELO)\b/i){
     print $client $tls ? "250-smtp.integration.test\r\n250 AUTH PLAIN LOGIN\r\n" : "250-smtp.integration.test\r\n250-STARTTLS\r\n250 HELP\r\n";
    }elsif($line=~/^STARTTLS$/i){
     print $client "220 Start TLS\r\n";
     $client=IO::Socket::SSL->start_SSL($client,SSL_server=>1,SSL_cert_file=>"$d/cert.pem",SSL_key_file=>"$d/key.pem",SSL_verify_mode=>0) or die "TLS negotiation ended\n";
     $client->autoflush(1);$tls=1;
    }elsif($line=~/^AUTH (PLAIN|LOGIN)(?: (.*))?$/i && $tls){
     my ($mechanism,$value)=(uc($1),$2);
     my ($user,$pass);
     if($mechanism eq 'PLAIN'){
      unless(defined($value) && length($value)){print $client "334 \r\n";$value=<$client>}
      my @parts=split /\0/,decode_base64($value//'');($user,$pass)=@parts[-2,-1];
     }else{
      if(defined $value && length $value){$user=decode_base64($value)}
      else{print $client "334 VXNlcm5hbWU6\r\n";$user=decode_base64(scalar(<$client>)//'')}
      print $client "334 UGFzc3dvcmQ6\r\n";$pass=decode_base64(scalar(<$client>)//'');
     }
     $auth=defined($user) && defined($pass) && $user eq 'integration-user' && $pass eq 'not-a-real-smtp-password';
     print $client $auth ? "235 2.7.0 Authenticated\r\n" : "535 5.7.8 Authentication failed\r\n";
    }elsif($line=~/^MAIL FROM:\s*<([^>]*)>/i && $tls && $auth){$sender=$1;@recips=();print $client "250 Sender accepted\r\n"}
    elsif($line=~/^RCPT TO:\s*<([^>]*)>/i && $auth){push @recips,$1;print $client "250 Recipient accepted\r\n"}
    elsif($line=~/^DATA$/i && $auth){
     print $client "354 End with dot\r\n";my $body='';
     while(my $part=<$client>){last if $part eq ".\r\n" || $part eq ".\n";$part=~s/^\.\././;$body.=$part}
     write_text("$d/delivered.eml",$body);
     write_text("$d/envelope.json",json({sender=>$sender,recipients=>\@recips,authenticated=>$auth?JSON::PP::true:JSON::PP::false}));
     print $client "250 2.0.0 Accepted\r\n";
    }elsif($line=~/^QUIT$/i){print $client "221 Bye\r\n";last}
    elsif($line=~/^RSET$/i){$sender='';@recips=();print $client "250 Reset\r\n"}
    else{print $client "530 Authentication and STARTTLS required\r\n"}
   }
  };
  close $client if $client;
 }
 exit 0;
}
for(1..40){last if -f "$d/ready";die "Synthetic SMTP server failed\n" if waitpid($server,WNOHANG)>0;select undef,undef,undef,.25}
die "SMTP readiness timed out\n" unless -f "$d/ready";
sub credentials {
 write_text("$d/credentials.json",json({username=>'integration-user',password=>$_[0]}));
 chmod 0600,"$d/credentials.json";chown 10001,10001,"$d/credentials.json" or die $!;
}
sub send_message {
 my ($trust)=@_;
 my @args=('docker','run','--rm','--user','10001:10001','--add-host','smtp.integration.test:host-gateway',
 '-e','SMTP_HOST=smtp.integration.test','-e','SMTP_PORT=587','-e','ACT_SMTP_FROM=sender@example.invalid',
 '-e','ACT_SMTP_FROM_NAME=Perl Community Conference','-v',"$d/credentials.json:/run/secrets/ses_smtp:ro",
 '-v',"$d/send.pl:/tmp/send.pl:ro");
 push @args,('-v',"$d/ca.pem:/etc/ssl/certs/ca-certificates.crt:ro") if $trust;
 push @args,($image,'perl','-I/opt/act/lib','/tmp/send.pl');
 local $SIG{ALRM}=sub{die "SMTP test timed out\n"};alarm 50;
 my @result=attempt(@args);alarm 0;return @result;
}
credentials('not-a-real-smtp-password');
my ($status,$out,$err)=send_message(0);
ok($status,'untrusted TLS certificate rejected');
ok(!-f "$d/delivered.eml",'no delivery on certificate failure');
unlike($err,qr/not-a-real-smtp-password/,'TLS error does not expose secret');
($status,$out,$err)=send_message(1);
is($status,0,'verified STARTTLS and AUTH delivery');
BAIL_OUT('Trusted test delivery failed') if $status;
my $envelope=decode_json_text(read_text("$d/envelope.json"));
ok($envelope->{authenticated},'AUTH required');
is($envelope->{sender},'sender@example.invalid','approved envelope sender');
is_deeply([sort @{$envelope->{recipients}}],[sort qw(recipient@example.invalid copy@example.invalid hidden@example.invalid)],'To Cc Bcc recipients preserved without duplicates');
my $message=read_text("$d/delivered.eml");
unlike($message,qr/^Bcc:/mi,'Bcc hidden from delivered headers');
like($message,qr/Synthetic direct SMTP body\./,'message body preserved');
like($message,qr/^From:.*Perl Community Conference.*<sender\@example.invalid>/mi,'sender display name preserved');
unlink "$d/delivered.eml";
credentials('wrong-password-for-negative-test');
($status,$out,$err)=send_message(1);
ok($status,'authentication failure reported');
ok(!-f "$d/delivered.eml",'bad authentication cannot deliver');
unlike($err,qr/wrong-password-for-negative-test/,'auth error does not expose secret');
chmod 0644,"$d/credentials.json";
($status,$out,$err)=send_message(1);
ok($status && $err=~/must be private/,'public credential file rejected');
done_testing;
