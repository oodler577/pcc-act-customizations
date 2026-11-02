#!/usr/bin/env perl
use strict;
use warnings;
use Playwright;
use Test::More;
my $base=shift || 'http://127.0.0.1:8765/conference';
die "Use an isolated local preview\n" unless $base =~ m{^http://127\.0\.0\.1:\d+/};
my $pw=Playwright->new();
my $browser=$pw->launch(type=>'chrome',headless=>1,args=>['--no-sandbox']);
my $page=$browser->newPage();
for my $width(1440,390) {
 $page->setViewportSize({width=>$width,height=>900});
 for my $state(qw(new edit admin error)) {
   $page->goto("$base/proposal-$state.html",{waitUntil=>'networkidle'});
   my $result=$page->evaluate(q{
     return {
       overflow: document.documentElement.scrollWidth > innerWidth,
       duplicates: [...document.querySelectorAll('[id]')].map(e=>e.id).filter((id,i,a)=>a.indexOf(id)!==i),
       qaHidden: document.querySelector('#pcc-qa-field').hidden,
       qa: document.querySelector('#pcc-qa').value,
       timezone: document.querySelector('#pcc-timezone').value,
       aiText: document.querySelector('#pcc-ai_generated').value,
       errors: !!document.querySelector('[role=alert]'),
       nativeDuration: !!document.querySelector('[name=duration]'),
       adminUser: !!document.querySelector('[name=user_id]')
     };
   });
   ok(!$result->{overflow},"$state $width: no horizontal overflow");
   is_deeply($result->{duplicates},[],"$state $width: unique control IDs");
   ok($result->{nativeDuration},"$state $width: native duration retained");
   is(!!$result->{adminUser},$state eq 'admin'?1:'',"$state $width: organizer controls");
   if($state ne 'new') {
     is($result->{qa},'yes',"$state $width: saved Q&A restored");
     is($result->{timezone},'America/Chicago',"$state $width: saved timezone");
     is($result->{aiText},'<script>alert(1)</script>',"$state $width: disclosure rendered as text");
     ok(!$result->{qaHidden},"$state $width: recorded Q&A visible");
   } else {
     ok($result->{qaHidden},"new $width: Q&A initially hidden");
     $page->selectOption('#pcc-delivery','prerecorded');
     my $visible=$page->evaluate(q{return !document.querySelector('#pcc-qa-field').hidden && document.querySelector('#pcc-qa').required;});
     ok($visible,"new $width: choosing prerecorded reveals required Q&A");
     $page->selectOption('#pcc-qa','unsure');
     $page->selectOption('#pcc-delivery','live_remote');
     ok($page->evaluate(q{return document.querySelector('#pcc-qa-field').hidden && !document.querySelector('#pcc-qa').required;}),"new $width: live remote removes Q&A requirement");
   }
   ok($result->{errors},"error $width: validation message shown") if $state eq 'error';
 }
}
$browser->close();$pw->quit();
done_testing;
