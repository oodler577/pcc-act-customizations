# English-only site, disabled wiki, and sharing metadata

Run as root on the ACT server, after pulling master:

```sh
cd /opt/pcc-act-styles
python3 scripts/update-site.py /home/sciperlconf/act/deploy
./scripts/apply-theme.sh /home/sciperlconf/act/deploy conference
cd /home/sciperlconf/act/deploy
docker compose build act &&
docker compose up -d --no-deps --force-recreate act
```

Requires the existing direct SMTP image setup. The helper preserves credentials and
all other conference settings. It backs up the conference config in deploy/backups.
The theme installer separately backs up the conference templates and assets.

The conference offers English only. Saved unsupported language sessions reset to
the configured default. The menu omits language switching and the wiki. Both wiki
handlers return 404 for every action, including view/history/diff and edits; an
anonymous edit request may first be redirected to login by ACT authentication.
Existing wiki data is preserved. Rebuilding and recreating ACT is required to
activate these handler changes; a theme-only restart is insufficient.

The homepage has a canonical URL, description, Open Graph and Twitter card tags,
and a 1200×630 JPEG using a crop of the bundled official oyster artwork. Titles
are HTML escaped. Only the homepage is indexable by default; other pages use
noindex,follow so login, registration confirmations and account URLs do not enter
search results. Public talks/news can receive dedicated indexing rules later.
No event dates, venue or event structured data are invented.

Validate after deployment:

```sh
curl -sS -o /dev/null -w 'Wiki: %{http_code}\n' https://science.perlcommunity.org/conference/wiki
curl -sS -o /dev/null -w 'Wiki history: %{http_code}\n' 'https://science.perlcommunity.org/conference/wiki?action=history'
curl -sS -o /dev/null -w 'Social image: %{http_code}\n' https://science.perlcommunity.org/conference/images/pcc-social.jpg
```

Expect wiki responses 404 and image 200. Verify the navigation while logged in
and out, and inspect the homepage source for og:image and canonical. Social
services can cache older previews until their sharing debugger is asked to refresh.

Theme rollback uses restore-theme.sh and its printed backup. To roll back the
application changes, restore the previous SMTP build context from the prior git
revision, restore the backed-up conference config, then rebuild/recreate ACT.
