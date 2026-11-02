# Winter 2026 edition

One ACT installation serves both the general PCC site at /conference/ and the
Winter 2026 edition at /winter2026/. The dates are December 17–18, 2026,
America/Chicago (Austin); the scheduling window covers those two entire local
days. Actual session start times remain organizer choices.

Source: https://blogs.perl.org/users/oodler_577/2026/10/save-the-date---winter-pcc-cfp-details-coming-soon.html

The public profile and edition home page live in editions/winter2026/. Reapplying
the theme retains that edition-specific home page. Canonical/social URLs use each
conference's configured full_uri. Journal links point to science.perlcommunity.org
rather than a /spj path on the conference hostname.

## Deploy on production

Use the refreshed checkout after the earlier history rewrite. The development
workspace cannot directly modify the production ACT server.

```bash
cd /opt/pcc-act-styles
git pull --ff-only
perl scripts/setup-proposals.pl /home/sciperlconf/act/deploy
docker compose --project-directory /home/sciperlconf/act/deploy build act
docker compose --project-directory /home/sciperlconf/act/deploy up -d --no-deps --force-recreate act
```

Only after the build and recreation succeed, create the edition. Replace
EXISTING_ADMIN_LOGIN with your existing ACT login; this is not an email address.

```bash
perl scripts/create-conference.pl /home/sciperlconf/act/deploy --admin-login EXISTING_ADMIN_LOGIN
./scripts/apply-theme.sh /home/sciperlconf/act/deploy conference
```

The helper validates the running proposal code, backs up the global config,
creates the edition's theme/configuration files, and enables it in the global
conference list. It creates only the named administrator's participation and six
organizer rights, two tracks (General Perl; Science Perl / Science Perl Journal),
and an invoice counter. Existing user accounts are shared; no existing attendee
registrations, proposals, rights, tracks, events, payments or uploads are copied
or moved. No email is sent. Repeated creation is refused to protect existing data.
Registration and talk proposals are open; public scheduling and payments remain
closed. A registration record does not imply a paid admission ticket.

This needs the existing conferences directory bind-mounted into ACT (rather than
only the conference subdirectory). The helper verifies local HTTP after restarting
ACT. Database changes are a transaction. A failure before the transaction commits
removes the staged edition directory; after commit, files/records are retained for
repair, and the backup path is printed. Do not rerun creation over partial state.

## Proxy and checks

The conference.perlcommunity.org server block previously configured with
location / proxy_pass http://127.0.0.1:5000 already forwards /winter2026/. That
requires no new certificate, container, database, port or Nginx change. The science
hostname's selective /conference/ route does not automatically serve /winter2026/;
use the conference hostname for this edition.

```bash
curl -sS -o /dev/null -w 'Winter home: %{http_code}\n' https://conference.perlcommunity.org/winter2026/
curl -sS -o /dev/null -w 'Registration: %{http_code}\n' https://conference.perlcommunity.org/winter2026/register
```

Expect 200. Log in using your existing account; edition-specific participation
and rights are separate, so use /winter2026/ when administering Winter 2026.
Check Manage talks, Tracks, the December 17–18 date choices, America/Chicago,
registration and a proposal before public announcement. Use the Winter edition
registration/proposal links, not the older /conference/ forms.

The general site retains its previous records and links to Winter 2026. It is
not silently repurposed as another event. The existing /conference/ forms are not
redirected or modified by this helper; disabling obsolete registrations can be a
separate deliberate step after any in-progress confirmations are accounted for.

## Recovery

To disable the new edition without deleting records, restore conf/act.ini from
the printed global-act.ini backup and restart only act. Retain the new directory
and database records until the cause is understood. Do not remove shared users.
For a later edition, prepare a reviewed profile and home page under editions/,
then use --edition ID. The helper has no production credentials or account login
hard-coded in it. Full stack and browser checks on the production configuration
remain necessary; development fixtures use synthetic Docker/database responses.
