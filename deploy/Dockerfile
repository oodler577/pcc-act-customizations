FROM perl:5.40-bookworm
WORKDIR /opt/act
RUN apt-get update && apt-get install -y --no-install-recommends pwgen && rm -rf /var/lib/apt/lists/* && mkdir -p /opt/acthome
COPY cpanfile .
RUN cpanm --notest IPC::System::Simple && cpanm --notest XML::Atom && cpanm --installdeps .
COPY wwwdocs /opt/acthome/wwwdocs
COPY templates /opt/acthome/templates
COPY po /opt/acthome/po
COPY . .
RUN cpanm --notest Starman Email::Send::SMTP
ENTRYPOINT ["/opt/act/docker-entrypoint.sh"]
CMD ["plackup", "app.psgi"]
