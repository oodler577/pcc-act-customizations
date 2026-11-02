# PCC talk proposals

The form stores a versioned JSON block at the end of the existing talks.comment text field. Ordinary comments remain separate in the editor. Duration uses ACT's native duration/lightning fields. Paper/talk choice is stored in the block; organizer track assignments remain independent. No schema migration or track records are needed.

Details include paper/talk type, delivery, IANA time zone, local time preferences, constraints, prerecorded live Q&A, longer-duration requests, AI extent and optional percentage with its basis, AI output, presenter effort and verification. These details are separate from the public abstract. Unknown metadata keys are preserved; corrupt blocks fail without overwriting data. Server validation works without JavaScript; JavaScript only controls Q&A visibility. Existing ACT permissions and acceptance/scheduling logic are retained. Organizers may maintain legacy proposals without filling in answers on behalf of the speaker.

## Deploy

On production, stage the code and build the existing direct-SMTP ACT image:

```bash
cd /opt/pcc-act-styles
git pull --ff-only https://github.com/oodler577/pcc-act-customizations.git master
python3 scripts/setup-proposals.py /home/sciperlconf/act/deploy
docker compose --project-directory /home/sciperlconf/act/deploy build act
```

Only after the image build succeeds (activation verifies the running code):

```bash
docker compose --project-directory /home/sciperlconf/act/deploy up -d --no-deps --force-recreate act
python3 scripts/setup-proposals.py /home/sciperlconf/act/deploy --activate
./scripts/apply-theme.sh /home/sciperlconf/act/deploy conference
```

Helpers print backup paths. No other service needs rebuilding. The activation marker enables future theme applications to refresh the form; without it, theme-only deployments retain the upstream form. New choices are 30 and 55 minutes, plus native lightning talks. Existing assigned lengths remain intact. Longer talks are requests for organizer agreement, not automatic schedule assignments.

Check a proposal and edit it as both speaker and organizer. Verify saved answers, ordinary comments, assigned duration and organizer track assignment. Organizer CSV export also contains the metadata in Comments. Organizer notification emails include the comment details; configure recipients accordingly. No production test submissions are made by the development tests.

## Rollback

Remove the deploy directory's .pcc-proposals-enabled marker. Restore the conference configuration and template from the printed backups; remove the custom actdocs/templates/talk/add if no previous override existed. Restore the previous handler source or image and recreate only act. Saved proposal details remain in Comments. Do not delete database data.

## Development

Run prove -v tests/proposals.t tests/proposal-handler.t. Handler tests require ACT_REFERENCE_LIB pointing to the pinned upstream lib directory (the development VM defaults to /opt/pcc-browser/act-reference/lib), DateTime, Email::Valid, and Text::Diff. They exercise the actual handler and form validator with isolated storage/template doubles. Metadata tests cover round trips and invalid inputs. Browser checks use Perl Playwright against a local preview.

The handler override is based on upstream Act commit 9af60d83390335bdbaeebaa2eb6bc44aa75ecfde. Compare it with upstream when upgrading. No upstream fork is required, but this override is an application customization to maintain.

To reproduce browser fixtures, run perl tests/render-proposals.pl OUTPUT_DIRECTORY, serve that directory locally on port 8765, and run tests/proposal-browser.pl with the Perl Playwright environment. The renderer uses pinned upstream templates and synthetic data, not production accounts. Derived ACT handler/template licensing is included under licenses/act/.
