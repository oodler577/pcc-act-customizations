#!/usr/bin/env perl
use strict;
use warnings;
use Playwright;
use JSON::MaybeXS qw(encode_json);
use File::Path qw(make_path);
use Cwd qw(abs_path);

my ($url, $output) = @ARGV;
die "Usage: $0 URL OUTPUT_DIRECTORY\n" unless $url && $output;
make_path($output);
$output = abs_path($output);
my $pw = Playwright->new();
my $browser = $pw->launch(type => 'chrome', headless => 1,
    args => $> == 0 ? ['--no-sandbox'] : []);
my $page = $browser->newPage();
my @results;
for my $viewport (
    { width => 1440, height => 1100 },
    { width => 390, height => 844 },
) {
    $page->setViewportSize($viewport);
    my $response = $page->goto($url, {waitUntil => 'networkidle', timeout => 45000});
    die "HTTP failure\n" if $response && $response->status() >= 400;
    my $state = $page->evaluate(q{
        return {
            title: document.title,
            width: innerWidth,
            overflow: document.documentElement.scrollWidth > innerWidth,
            brokenImages: [...document.images].filter(i => !i.complete || i.naturalWidth === 0).map(i => i.getAttribute('src')),
            headerColor: getComputedStyle(document.querySelector('.site-header') || document.querySelector('.pkp_structure_head') || document.body).backgroundColor,
            font: getComputedStyle(document.body).fontFamily
        };
    });
    $page->screenshot({path => "$output/viewport-$viewport->{width}.png", fullPage => 1});
    push @results, $state;
}
$browser->close();
$pw->quit();
print encode_json(\@results), "\n";
die "Browser checks failed\n" if grep { $_->{overflow} || @{$_->{brokenImages}} } @results;
