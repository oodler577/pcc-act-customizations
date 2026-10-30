ARG ACT_BASE_IMAGE=science-act:9af60d8
FROM ${ACT_BASE_IMAGE}
USER root
RUN cpanm --notest Email::Sender::Transport::SMTP IO::Socket::SSL Authen::SASL Net::SMTP Email::Address
COPY lib/ /opt/act/lib/
