use strict;use warnings;
use Test::More;
use FindBin;use lib "$FindBin::Bin/../scripts/lib";
use Pcc::Deploy qw(read_text write_text attempt);
use Pcc::HomeProxy qw(home_proxy_config);
use File::Temp qw(tempdir);
use File::Path qw(make_path);
my $config=<<'CONF';
worker_processes 1;
events { worker_connections 256; }
http {
    server {
        listen 443 ssl;
        server_name science.perlcommunity.org;
        location = /conference { return 301 /conference/; }
        location ^~ /conference/ { proxy_pass http://127.0.0.1:5000; }
        location ^~ /photos/ { proxy_pass http://127.0.0.1:5000; }
        location / { proxy_pass https://127.0.0.1:8443; }
    }
    server {
        listen 443 ssl;
        server_name conference.perlcommunity.org;
        ssl_certificate /example/fullchain.pem;
        ssl_certificate_key /example/key.pem;
        location = / { return 302 /conference/; }
        location = /conference { return 301 /conference/; }
        location / { proxy_pass http://127.0.0.1:5000; }
    }
}
CONF
my $new=home_proxy_config($config,'conference.perlcommunity.org');
like($new,qr{location = / \{\s*proxy_pass http://127\.0\.0\.1:5000/conference/;}s,'root internally serves existing ACT home');
like($new,qr{proxy_pass https://127.0.0.1:8443;},'OJS upstream preserved');
like($new,qr{return 308 https://conference.perlcommunity.org\$request_uri;},'science ACT paths redirect to conference host');
unlike($new,qr{location = / \{ return 302 /conference/;},'old root redirect removed');
is(()=$new=~/PCC ROOT HOME BEGIN/g,1,'one managed routing block');
is(home_proxy_config($new,'conference.perlcommunity.org'),$new,'reapplication is idempotent');
eval {home_proxy_config($config,'missing.example')};like($@,qr/exactly one/,'missing host rejected');
my $custom=$config;$custom=~s{location = / \{ return 302 /conference/; \}}{location = / { proxy_pass http://custom.example; }};
eval {home_proxy_config($custom,'conference.perlcommunity.org')};like($@,qr/Custom homepage handler/,'unknown homepage behavior requires review');
my $tmp=tempdir(CLEANUP=>1);make_path("$tmp/bin","$tmp/proxy","$tmp/act/conferences/conference/actdocs/conf");
write_text("$tmp/proxy/nginx.conf",$config);
my $ini="$tmp/act/conferences/conference/actdocs/conf/act.ini";write_text($ini,"[general]\nfull_uri = https://old.example/conference/\nname_en = PCC\n");
write_text("$tmp/bin/docker",<<'DOCKER');
#!/usr/bin/env perl
use strict;use warnings;
exit 1 if $ENV{PCC_BAD_NGINX} && join(' ',@ARGV)=~/nginx -t/;
exit 0;
DOCKER
chmod 0755,"$tmp/bin/docker";local $ENV{PATH}="$tmp/bin:$ENV{PATH}";
SKIP: {
 skip 'Live config helper requires root',5 if $>;
 {local $ENV{PCC_BAD_NGINX}=1;
  my ($status)=attempt($^X,"$FindBin::Bin/../scripts/setup-home-proxy.pl","$tmp/proxy","$tmp/act");
  ok($status,'failed syntax check aborts setup');
 }
 is(read_text("$tmp/proxy/nginx.conf"),$config,'Nginx restored after validation failure');
 like(read_text($ini),qr/old.example/,'ACT config restored after failure');
 my ($status)=attempt($^X,"$FindBin::Bin/../scripts/setup-home-proxy.pl","$tmp/proxy","$tmp/act");
 is($status,0,'root-home setup succeeds after validation');
 like(read_text($ini),qr{full_uri = https://conference.perlcommunity.org/},'general public URL points to root');
}
done_testing;
