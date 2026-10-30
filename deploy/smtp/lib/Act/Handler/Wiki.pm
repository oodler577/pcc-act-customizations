package Act::Handler::Wiki;
use strict;
use warnings;
use parent 'Act::Handler';
# PCC does not offer a wiki. Block every action, including direct requests.
sub handler { return [404, ['Content-Type' => 'text/plain; charset=utf-8', 'Cache-Control' => 'no-store'], ["Not found\n"]]; }
1;
