package Pcc::SMTP;
use strict;
use warnings;
use JSON::PP qw(decode_json);
use Email::Address;
use Email::Simple;
use Email::Sender::Simple ();
use Email::Sender::Transport::SMTP;
use IO::Socket::SSL qw(SSL_VERIFY_PEER);

sub new {
    my ($class, %args) = @_;
    my $file = $args{config_file} or die "SMTP credential file not specified\n";
    my @st = stat $file;
    die "SMTP credential file must be private (mode 0600 or 0400)\n"
        unless @st && !($st[2] & 0077);
    open my $fh, '<:raw', $file or die "Cannot read SMTP credential file\n";
    local $/;
    my $config = eval { decode_json(<$fh>) };
    close $fh;
    die "Invalid SMTP credential file\n" unless ref $config eq 'HASH';
    for my $key (qw(username password)) {
        die "Missing or invalid SMTP credential field: $key\n"
            unless defined($config->{$key}) && !ref($config->{$key})
            && length($config->{$key}) && $config->{$key} !~ /[\r\n\x00]/;
    }
    my $host = $ENV{SMTP_HOST} // '';
    my $port = $ENV{SMTP_PORT} // 587;
    my $from = $ENV{ACT_SMTP_FROM} // '';
    my $name = $ENV{ACT_SMTP_FROM_NAME} // '';
    die "Invalid SMTP sender name\n" if $name =~ /[\r\n\x00]/;
    die "Invalid SMTP host\n" unless $host =~ /\A[A-Za-z0-9.-]+\z/;
    die "Invalid SMTP port\n" unless $port =~ /\A[0-9]+\z/ && $port > 0 && $port < 65536;
    die "Invalid SMTP envelope sender\n" unless $from =~ /\A[A-Za-z0-9._%+-]+\@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\z/;
    my $transport = Email::Sender::Transport::SMTP->new(
        host => $host, port => 0+$port,
        ssl => 'starttls',
        sasl_username => $config->{username},
        sasl_password => $config->{password},
        timeout => 30,
        ssl_options => {
            SSL_verify_mode => SSL_VERIFY_PEER,
            SSL_verifycn_scheme => 'smtp',
            SSL_verifycn_name => $host,
            SSL_hostname => $host,
            SSL_ca_file => '/etc/ssl/certs/ca-certificates.crt',
        },
    );
    return bless { transport => $transport, from => $from, name => $name }, $class;
}

sub send {
    my ($self, $email) = @_;
    # Work on a copy; preserve Act's original MIME headers/body.
    my $message = Email::Simple->new($email->as_string);
    if (length $self->{name}) {
        $message->header_set('From', Email::Address->new($self->{name}, $self->{from})->format);
    }
    my (@to, %seen);
    for my $header (qw(To Cc Bcc)) {
        for my $value ($message->header($header)) {
            for my $address (Email::Address->parse($value)) {
                my $recipient = $address->address;
                push @to, $recipient unless $seen{lc $recipient}++;
            }
        }
    }
    die "ACT email has no recipients\n" unless @to;
    # Bcc recipients remain in the SMTP envelope but not the transmitted header.
    $message->header_set('Bcc');
    my $ok = eval {
        Email::Sender::Simple->send($message, {
            transport => $self->{transport},
            from => $self->{from},
            to => \@to,
        });
        1;
    };
    unless ($ok) {
        # Do not stringify transport objects or credentials into logs/pages.
        my $error = $@;
        my $code = eval { $error->code } // 'transport';
        $code = 'transport' unless $code =~ /\A[0-9]{3}\z/;
        warn "ACT SMTP submission failed (code $code)\n";
        die "ACT could not send email. Please try again later or contact the organizers.\n";
    }
    return 1;
}
1;
