#!/usr/bin/env perl
use strict;use warnings;
use FindBin;use lib "$FindBin::Bin/lib";
use Pcc::Deploy qw(read_text write_text decode_json_text json prompt root_required);
root_required();
my $path=shift // die "Usage: $0 PRIVATE_CREDENTIAL_JSON\n";die "Unexpected arguments\n" if @ARGV;
my @st=lstat($path);die "Expected a private regular credential file\n" unless @st && -f _ && !-l _ && !($st[2]&0077);
my $config=decode_json_text(read_text($path));
my $username=prompt('New SMTP username: ',0);$username=~s/^\s+|\s+$//g;
my $password=prompt('New SMTP password: ',1);
die "Passwords did not match; no changes made\n" unless $password eq prompt('Confirm password: ',1);
die "Invalid credentials; no changes made\n" unless length($username) && length($password) && "$username$password"!~/[\r\n\x00]/;
$config->{username}=$username;$config->{password}=$password;
# Keep the inode for an existing bind mount, as the documented restart reloads it.
write_text($path,json($config));chmod 0600,$path or die $!;
print "SMTP credentials updated privately. Restart act to reload them.\n";
