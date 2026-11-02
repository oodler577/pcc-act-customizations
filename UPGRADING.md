# ACT build pins, checkpoints and upgrades

## What is pinned

- ACT source: 9af60d83390335bdbaeebaa2eb6bc44aa75ecfde. scripts/build-image.sh refuses a different commit or tracked source modifications.
- Perl base: deploy/Dockerfile now uses the exact registry digest recorded in upstream-lock.json, rather than relying on a moving tag.
- Local customizations: Git commits identify the handler, SMTP, language/wiki overrides and conference templates. upstream-lock.json records reviewed upstream file hashes.

A fresh build is NOT yet fully reproducible: Debian apt packages and CPAN dependencies are resolved at build time. The derivative SMTP Dockerfile also defaults to a local science-act tag; a tag can be reassigned. Do not treat these tags as immutable pins. The checkpoint below records the exact running image IDs and the locally available configured ACT build base. Archiving those images retains the actual installed packages, independent of future package repositories.

This repository does not manage OJS or Nginx image updates. Run the checkpoint tool separately against their Compose directories if desired. No claim is made that their existing tags are pinned.

## Checkpoint before rebuilding or upgrading

On the production host, from this repository:

```bash
python3 scripts/checkpoint-images.py /home/sciperlconf/act/deploy --archive
```

The command prints a new private directory under deploy/backups. It records only whitelisted image metadata, running service/image mappings, available ACT build base IDs and the customization checkout commit. It does not write Compose configuration, environment variables, SMTP credentials or container identities into the manifest. It does not change running services or Compose settings. Stopped services are listed as missing; start or checkpoint them separately if they matter.

With --archive, images.tar.gz contains the binary images and a SHA-256 checksum. Docker images can contain anything copied into them: keep the archive private even though our Dockerfiles do not copy credentials. Ensure sufficient disk space and copy the checkpoint off the VM. Without --archive, metadata alone cannot recover deleted images. A checkpoint records the current repository commit, not proof that the running image was built from that commit.

Images are not a backup of PostgreSQL data, uploaded files, conference configuration, credentials or the theme. Back those up separately. Take a fresh checkpoint after a verified deployment as well as before it. Do not prune images needed for rollback until the archive has been verified.

## Restore exact images

In the checkpoint directory:

```bash
sha256sum -c images.tar.gz.sha256
gzip -dc images.tar.gz | docker image load
```

The generated images.lock.json is a final Compose overlay using exact image IDs and pull_policy never. To restore, explicitly list the deployment's normal Compose files in their usual order, then the lock overlay LAST, and use up --no-build --pull never. For example, if the deployment uses compose.yml and compose.override.yml:

```bash
docker compose --project-directory /home/sciperlconf/act/deploy \
  -f /home/sciperlconf/act/deploy/compose.yml \
  -f /home/sciperlconf/act/deploy/compose.override.yml \
  -f /ABSOLUTE/CHECKPOINT/images.lock.json \
  up -d --no-build --pull never
```

Use the actual filenames; do not omit normal overrides containing settings or secret mounts. Always validate that same file combination with config --quiet before restoring. For an ACT-only code rollback, append act to up so the database is not recreated. Do not run build with the lock overlay: image IDs are runtime references, not build output tags. Ordinary docker compose commands do not automatically load this overlay.

## Deliberate ACT upgrade

1. Checkpoint the running images and back up the databases, conference files, configuration and private secrets. Record the previous customization commit. Use an isolated test deployment with synthetic data and a mail sink; no SES delivery from tests.
2. Check out the candidate ACT revision in a separate clean source tree. Run python3 scripts/check-act-upgrade.py /path/to/candidate. It reports changed upstream files beneath our overrides. A match only means those tracked files match; it is not proof of overall compatibility.
3. Review changes in Act::Handler::Talk::Edit, the talk/add template, Act::Email, the language middleware, disabled wiki handlers, database migrations, dependency requirements and routing. Merge upstream fixes into our overrides rather than hiding them under an older copied handler.
4. Update the explicit source commit in scripts/build-image.sh, the image name/default base reference where needed, the reviewed file hashes in upstream-lock.json, and documentation together. Change the Perl digest intentionally when adopting a new base; record why. Never just change an image tag and skip review.
5. Rebuild the base ACT image with scripts/build-image.sh. For production, the base should remain the existing tested local image until the candidate passes. Update ACT_BASE_IMAGE in the deployment's private Compose build arguments to the tested new base. Staging helpers copy selected overrides, so ensure the complete reviewed deploy/smtp/lib tree is staged before rebuilding the derivative image. Do not copy production secrets into a build context.
6. Run prove -v tests/proposals.t tests/proposal-handler.t with ACT_REFERENCE_LIB set to the candidate's lib directory. Run SMTP TLS/authentication tests, the Perl Playwright proposal tests and real browser create/edit checks against the isolated ACT/PostgreSQL stack. Check organizer acceptance, assigned duration, track assignment, comments, CSV exports, saved metadata, registration, login, English-only UI and disabled wiki. Storage/template doubles do not replace this full-stack check.
7. Commit the upgrade and pin changes. Deploy only ACT first, following PROPOSALS.md for staged proposal code and activation. Run the documented production checks and take another image checkpoint. Keep rollback images and database backups; a database migration may require a database restore as well as the previous image.

Current proposal deployment instructions are in PROPOSALS.md; SMTP in MAIL.md; language/wiki updates in SITE-UPDATES.md. Future full dependency reproducibility would require a CPAN distribution lock plus a controlled Debian package snapshot, beyond the binary image checkpoint provided here.
