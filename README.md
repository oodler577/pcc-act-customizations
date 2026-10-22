# PCC Act styles

Conference-local Science Perl / Perl Community Conference theme for Act PSGI.
SPJ blue (#1e6292), blue links (#006798), white background, and a responsive layout; native organizer menus retained. General Perl conference wording includes a prominent science track.
The visible demo notice and provisional event wording are intentional.

## Install on an existing deployment

Use an account allowed to modify the conference files and run Docker.
The deployment must already contain a configured conference, a Compose `act`
service, and the upstream default menu templates. No database migration occurs.

```bash
git clone https://github.com/oodler577/pcc-act-styles.git
cd pcc-act-styles
git checkout master
./scripts/apply-theme.sh /path/to/act/deploy conference
./scripts/check.sh https://YOUR_HOST/conference
```

The installer creates a private backup in the destination deployment's
`backups/` directory, copies the theme files and official artwork, and restarts only Act.
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
dumps, user accounts, logs, or uploaded files. No account identities, deployment host
paths, or credentials are included in this repository. Branding is public
project content. Store machine-specific configuration outside this checkout.

## Visual references and logo provenance

Visual reference: https://science.perlcommunity.org/spj

The oyster is the actual logo embedded in official PCC artwork from:
https://www.perlcommunity.org/images/perl_community_conference_summer_2026__1500x1000.jpg

Artwork SHA-256: 9ddaa9d16afaf27e11018b63e9b191715563c8b11fe5dd6fa9c22af4cbc3385c

The original JPEG is bundled unchanged. CSS frames the oyster at source
rectangle (1150, 658, 330, 330); it does not recreate the mark or display the
old event dates. Artwork rights remain with their original owners.
The header links to /spj; no live journal stylesheet is imported. Noto Sans regular and bold are bundled from the journal’s public font assets,
with system sans-serif fallbacks. Font license: SIL Open Font License 1.1.

## Browser verification with Perl

`scripts/browser-check.pl URL OUTPUT_DIRECTORY` drives Chromium using the
CPAN `Playwright` client. Install the Perl module, its Node controller
dependencies, and the matching Chromium browser outside the repository.
Set PERL5LIB, NODE_PATH, and PATH as needed for a local installation.
The script captures desktop (1440px) and mobile (390px) screenshots and
checks horizontal overflow and broken images. Pass an output directory
outside this checkout. No browser control is implemented in Node or Python.

The theme was rendered with Template Toolkit and inspected through this
Perl client using representative navigation. This does not replace testing
logged-in Act organizer pages on the deployment after installation.
