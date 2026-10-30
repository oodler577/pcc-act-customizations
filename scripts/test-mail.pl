#!/usr/bin/env perl
# Run inside the Act container. One recipient is required explicitly.
use strict;
use warnings;
use Act::Config;
use Act::Email;
my $recipient = shift @ARGV;
die "Usage: perl -Ilib test-mail.pl RECIPIENT\n"
    unless $recipient && $recipient =~ /\A[^\s<>\@]+\@[^\s<>\@]+\.[^\s<>\@]+\z/;
Act::Email::send(
    from => $Config->email_sender_address,
    to => $recipient,
    subject => 'PCC ACT email delivery test',
    body => "This is a transactional email delivery test from the PCC ACT conference site.\n",
);
print "SMTP submission accepted. Verify delivery in the recipient inbox.\n";
