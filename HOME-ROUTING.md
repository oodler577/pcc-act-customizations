# Permanent PCC home at the hostname root

The general PCC home is https://conference.perlcommunity.org/ while ACT retains
its existing internal conference identifier. Winter 2026 stays at /winter2026/.
No database rows or conference identifiers are renamed.

On production, after pulling master and applying the current theme:

```bash
perl scripts/setup-home-proxy.pl /home/sciperlconf/proxy /home/sciperlconf/act/deploy
```

The helper backs up proxy/nginx.conf and the general conference configuration.
It replaces the known exact homepage redirects in the conference hostname's
server block, validates Nginx, sets the general conference full_uri to the root,
restarts only ACT and reloads Nginx. Unknown custom homepage handlers cause it to
stop before editing. It restores both files and attempts to restart/reload on a
validation or service failure. It prints the private backup directory.

Routes:

- / internally serves ACT's existing /conference/ homepage.
- /conference, /conference/, /conference/index.html and /index.html redirect to /.
- Public conduct.html, past-talks.html, impacts.html, donate.html, sponsors.html
  and speak.html are available at the root; their old /conference/ URLs redirect.
- Existing account/authentication routes retain their paths on the conference hostname.
- /winter2026/ and future edition paths pass through normally.
- ACT routes on science.perlcommunity.org redirect to the conference hostname;
  its OJS upstream and certificate configuration are preserved.

The shared wrapper uses the configured full_uri for canonical/social metadata
and the general home link. The clean public page aliases keep those canonical
URLs reachable. This is not a rewrite of arbitrary ACT forms or account URLs.

Verify:

```bash
curl -sS -o /dev/null -w 'Home: %{http_code}\n' https://conference.perlcommunity.org/
curl -sS -o /dev/null -w 'Old home: %{http_code}\n' https://conference.perlcommunity.org/conference/
curl -sS -o /dev/null -w 'Impacts: %{http_code}\n' https://conference.perlcommunity.org/impacts.html
curl -sS -o /dev/null -w 'Winter: %{http_code}\n' https://conference.perlcommunity.org/winter2026/
```

Expect 200, 301, 200, 200. Check login and the Science Perl Journal link as well.
To roll back, restore nginx.conf and conference-act.ini from the printed backup
to their original locations, restart ACT, run nginx -t, then reload Nginx. No
container recreation, OJS change, certificate issuance, or database migration is
required for the root routing step.
