package Pcc::HomeProxy;
use strict;use warnings;
use Exporter 'import';
our @EXPORT_OK=qw(home_proxy_config);
# Match braces while ignoring quoted strings and comments in Nginx config.
sub block_end {
 my ($text,$start)=@_;my ($depth,$quote,$escape,$comment)=(0,'',0,0);
 for(my $i=$start;$i<length($text);$i++){
  my $c=substr($text,$i,1);
  if($comment){$comment=0 if $c eq "\n";next}
  if($escape){$escape=0;next}
  if($c eq '\\'){$escape=1;next}
  if($quote){$quote='' if $c eq $quote;next}
  if($c eq '"' || $c eq "'"){$quote=$c;next}
  if($c eq '#'){$comment=1;next}
  $depth++ if $c eq '{';
  if($c eq '}'){return $i if --$depth==0}
 }
 die "Unbalanced Nginx block; no changes made\n";
}
sub home_proxy_config {
 my ($text,$host)=@_;die "Invalid hostname\n" unless $host=~/\A[a-z0-9.-]+\z/;
 my @servers;
 while($text=~/^[ \t]*server[ \t]*\{/mg){
  my $start=$-[0];my $open=$+[0]-1;my $end=block_end($text,$open);
  my $block=substr($text,$start,$end-$start+1);
  my @names=$block=~/^[ \t]*server_name[ \t]+([^;]+);/mg;
  push @servers,[$start,$end,$block] if grep {my @n=split /\s+/;grep {$_ eq $host} @n} @names;
  pos($text)=$end+1;
 }
 die "Expected exactly one server block for $host; no changes made\n" unless @servers==1;
 my ($start,$end,$block)=@{$servers[0]};
 die "Expected ACT catch-all proxy on port 5000; no changes made\n"
   unless $block=~/proxy_pass\s+http:\/\/127\.0\.0\.1:5000\s*;/;
 $block=~s{[ \t]*\# PCC ROOT HOME BEGIN\n.*?\# PCC ROOT HOME END\n}{}s;
 # Replace only the familiar exact homepage redirects, never arbitrary handlers.
 my @remove;
 while($block=~/^[ \t]*location[ \t]+=[ \t]+(\/[^\s{]*)[ \t]*\{/mg){
  my ($path,$ls,$lo)=($1,$-[0],$+[0]-1);
  my $le=block_end($block,$lo);
  if(grep {$_ eq $path} qw(/ /index.html /conference /conference/ /conference/index.html)){
   my $body=substr($block,$lo+1,$le-$lo-1);
   $body=~s/#[^\n]*//g;
   die "Custom homepage handler for $path needs review; no changes made\n"
     unless $body=~/\A\s*return\s+30[1278]\s+[^;]+;\s*\z/s;
   push @remove,[$ls,$le-$ls+1];
  }
  pos($block)=$le+1;
 }
 for my $range(reverse @remove){substr($block,$range->[0],$range->[1],'')}
 my $locations=<<'NGINX';
        # PCC ROOT HOME BEGIN
        location = / {
            proxy_pass http://127.0.0.1:5000/conference/;
        }
        location = /index.html { return 301 /$is_args$args; }
        location = /conference { return 301 /$is_args$args; }
        location = /conference/ { return 301 /$is_args$args; }
        location = /conference/index.html { return 301 /$is_args$args; }
        location ~ ^/conference/(conduct|past-talks|impacts|donate|sponsors|speak)\.html$ {
            return 301 /$1.html$is_args$args;
        }
        location ~ ^/(conduct|past-talks|impacts|donate|sponsors|speak)\.html$ {
            rewrite ^/(.*)$ /conference/$1 break;
            proxy_pass http://127.0.0.1:5000;
        }
        # PCC ROOT HOME END
NGINX
 # Put our public-page regexes ahead of existing regex locations.
 $block=~s/(?=^[ \t]*location\b)/$locations/m
  or die "No location directives found; no changes made\n";
 substr($text,$start,$end-$start+1,$block);
 return isolate_science($text,$host);
}
sub isolate_science {
 my ($text,$host)=@_;my @found;
 while($text=~/^[ \t]*server[ \t]*\{/mg){
  my ($start,$open)=($-[0],$+[0]-1);my $end=block_end($text,$open);
  my $block=substr($text,$start,$end-$start+1);
  push @found,[$start,$end,$block] if $block=~/^[ \t]*server_name[ \t]+science\.perlcommunity\.org[ \t]*;/m;
  pos($text)=$end+1;
 }
 die "Expected the science/OJS server block; no changes made\n" unless @found==1;
 my ($start,$end,$block)=@{$found[0]};
 die "Science server must retain its existing OJS upstream\n"
   unless $block=~/proxy_pass\s+https:\/\/127\.0\.0\.1:8443\s*;/;
 $block=~s{[ \t]*\# PCC ACT HOST REDIRECTS BEGIN\n.*?\# PCC ACT HOST REDIRECTS END\n}{}s;
 my @replace;
 while($block=~/^[ \t]*location\b[^{]*\{/mg){
  my ($begin,$open)=($-[0],$+[0]-1);my $close=block_end($block,$open);
  my $header=substr($block,$begin,$open-$begin);
  my $body=substr($block,$open+1,$close-$open-1);
  if($body=~/proxy_pass\s+http:\/\/127\.0\.0\.1:5000\s*;/){
   my $clean=$body;$clean=~s/#[^\n]*//g;
   die "Custom ACT location in science server needs review\n"
     unless $clean=~/\A\s*proxy_pass\s+http:\/\/127\.0\.0\.1:5000\s*;\s*\z/s;
   push @replace,[$open+1,$close-$open-1,' return 308 https://'.$host.'$request_uri; '];
  }elsif($header=~/location\s+=\s+\/conference\s*\z/){
   die "Custom science conference redirect needs review\n"
     unless $body=~/\A\s*return\s+30[1278]\s+[^;]+;\s*\z/s;
   push @replace,[$open+1,$close-$open-1,' return 308 https://'.$host.'/; '];
  }
  pos($block)=$close+1;
 }
 for my $range(reverse @replace){substr($block,$range->[0],$range->[1],$range->[2])}
 die "Science server still proxies ACT; no changes made\n" if $block=~/proxy_pass\s+http:\/\/127\.0\.0\.1:5000/;
 my $redirects="        # PCC ACT HOST REDIRECTS BEGIN\n".
  '        location = /conference/ { return 308 https://'.$host.'/; }'."\n".
  '        location ~ ^/(winter|summer)\d\d\d\d(?:/|$) { return 308 https://'.$host.'$request_uri; }'."\n".
  "        # PCC ACT HOST REDIRECTS END\n";
 $block=~s/(?=^[ \t]*location\b)/$redirects/m or die "No science locations found\n";
 substr($text,$start,$end-$start+1,$block);
 return $text;
}

1;
