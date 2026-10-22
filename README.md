# PCC Act styles

Conference-local Science Perl / Perl Community Conference theme for Act PSGI.
Navy, teal, and warm white; responsive layout; native organizer menus retained.
The visible demo notice and provisional event wording are intentional.

## Install on an existing deployment

Use an account allowed to modify the conference files and run Docker.
The deployment must already contain a configured conference, a Compose `act`
service, and the upstream default menu templates. No database migration occurs.

```bash
git clone git@github.com:oodler577/pcc-act-styles.git
cd pcc-act-styles
git checkout master
./scripts/apply-theme.sh /path/to/act/deploy conference
./scripts/check.sh https://YOUR_HOST/conference
```

The installer creates a private backup in the destination deployment's
`backups/` directory, copies three theme files, and restarts only Act.
It prints the exact rollback command. Restart briefly interrupts Act.
It does not change OJS, Nginx, databases, permissions, or certificate renewal.
Refresh the browser after installation. Test registration, login, organizer
menus, scheduling, long tables, and a narrow viewport before production use.
An account and working SMTP must be configured separately.

## Files

- `theme/actdocs/templates/ui`: shared page wrapper; keeps the native menu.
- `theme/actdocs/static/index.html`: conference landing page.
- `theme/wwwdocs/css/style.css`: theme and responsive rules.
- `scripts/apply-theme.sh`: backup and install.
- `scripts/restore-theme.sh`: restore a locally generated backup.
- `scripts/check.sh`: HTTP checks (not a full browser or authentication test).
- `scripts/build-image.sh` and `deploy/Dockerfile`: rebuild the Act image.

## Application image

This is a theme repository, not a copy of Act or a complete hosting stack.
The build helper expects a clean checkout of book/Act at
`9af60d83390335bdbaeebaa2eb6bc44aa75ecfde`. It builds
`science-act:9af60d8` with Perl 5.40 Bookworm, Starman, and SMTP support.

```bash
git clone https://github.com/book/Act.git /path/to/act/source
git -C /path/to/act/source checkout 9af60d83390335bdbaeebaa2eb6bc44aa75ecfde
./scripts/build-image.sh /path/to/act/source
```

Base tags and CPAN resolution can change; retain image digests or export the
built image when exact binary reproduction is needed. MAKEFLAGS requests
serial make builds but does not impose a container memory limit.

## Hosting integration

Act must receive the original conference URL path. With a `/conference/`
conference, forward that prefix and `/photos/` to Act. The theme also uses
these upstream shared assets: `/css/act-base.css`, `/css/schedule.css`,
`/js/jquery.js`, `/js/act.js`, and the upstream photo/favorite images under
`/images/`. Preserve other application routes. Configure HTTPS, backups,
SMTP, credentials, and certificate renewal in the destination deployment.

Never commit live configuration, environment files, certificates, database
dumps, user accounts, logs, or uploaded files. No account identities, host
paths, or credentials are included in this repository. Branding is public
project content. Store machine-specific configuration outside this checkout.
