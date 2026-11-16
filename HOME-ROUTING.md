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
- Public conduct.html, past-talks.html, impacts.html and speak.html are available
  at the root; their old /conference/ URLs redirect.
- The only donation/sponsorship page is /conference/donate.html. All shared
  Donate/Sponsor links and edition support links point there. /donate.html and
  edition donate.html URLs redirect to it; sponsors.html aliases redirect to its
  #sponsor section. Query strings are retained. The exact canonical route is
  proxied directly to ACT, so it does not enter the legacy redirect rules.
- Applying the theme to an edition removes its old donate.html after backing it
  up. Apply the theme to conference first, then the editions, and rerun the home
  proxy helper so old links continue to work.
- News lives at /conference/news, with article URLs /conference/news/ID and
  the shared Atom feed at /conference/atom/en.xml. Root and edition news/feed
  aliases redirect there, preserving the article ID, language and query string.
  News Administration links use /conference/newsadmin; legacy newsadmin/newsedit
  URLs use method-preserving 308 redirects. ACT still checks news permissions in
  the general conference; no access rights are granted or changed.
- Existing news records and publication states are not modified. The public
  Winter 2026 news page was empty when this change was prepared on 2026-11-16.
  General-site news continues to use its existing records and homepage updates.
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
