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
       aiText: document.querySelector('#pcc-ai_notes').value,
       errors: !!document.querySelector('[role=alert]'),
       nativeDuration: !!document.querySelector('[name=duration]'),
       adminUser: !!document.querySelector('[name=user_id]'),
       roomAbsent: !document.querySelector('[name=room]'),
       talkTypeAbsent: !document.querySelector('[name=pcc_talk_type]'),
       hiddenRows: !document.querySelector('input[name=tags],select[name=lang],input[name=url_video1]'),
       english: document.querySelector('[name=lang]').value,
       aiBoxes: document.querySelectorAll('textarea[name^=pcc_ai]').length,
       timezoneOptions: document.querySelectorAll('#pcc-timezone option').length,
       recordingLocked: !!document.querySelector('input[type=checkbox][disabled]'),
       labelWidth: document.querySelector('.pcc-proposal-fields tr td').getBoundingClientRect().width
     };
   });
   ok(!$result->{overflow},"$state $width: no horizontal overflow");
   is_deeply($result->{duplicates},[],"$state $width: unique control IDs");
   ok($result->{roomAbsent},"$state $width: room control absent");
   ok($result->{talkTypeAbsent},"$state $width: retired talk type absent");
   ok($result->{hiddenRows},"$state $width: tags, language and video URL controls hidden");
   is($result->{english},'en',"$state $width: English assumed");
   is($result->{aiBoxes},1,"$state $width: one AI comment box");
   ok($result->{timezoneOptions}>100,"$state $width: standard timezone choices");
   ok($result->{recordingLocked},"$state $width: recording policy fixed");
   ok($result->{labelWidth}>=135,"$state $width: label column has room") if $width>650;
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
