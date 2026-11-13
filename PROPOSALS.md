# PCC talk proposals

The form stores a versioned JSON block at the end of the existing talks.comment text field. Ordinary comments remain separate in the editor. Duration uses ACT's native duration/lightning fields. Speakers select a native ACT talk track. Science submissions require an associated paper title or acknowledgment of the one-time paperless DOI exception; organizers may maintain legacy records with incomplete metadata. Previously saved custom talk-type metadata is retained but no longer collected. No schema migration or track records are needed.

Details include the associated SPJ paper title for Science track talks, delivery, IANA time zone, local time preferences, constraints, prerecorded live Q&A, and a single AI/human-effort comment box. Time zones are chosen from standard named regions (common choices first); seasonal clock changes are handled by their IANA identifiers. The form assumes English and hides Tags and Video URLs without clearing existing values. Recording/publication is a stated submission requirement; the displayed recording control is fixed, and speaker submissions confirm it. Organizer edits preserve existing recording consent rather than inventing it. Older separate AI answers are combined for display and retained in stored metadata. These details are separate from the public abstract. Unknown metadata keys are preserved; corrupt blocks fail without overwriting data. Server validation works without JavaScript; JavaScript only controls Q&A visibility. Existing ACT permissions and acceptance/scheduling logic are retained. Organizers may maintain legacy proposals without filling in answers on behalf of the speaker.

## Deploy

On production, stage the code and build the existing direct-SMTP ACT image:

```bash
cd /opt/pcc-act-styles
git pull --ff-only https://github.com/oodler577/pcc-act-customizations.git master
perl scripts/setup-proposals.pl /home/sciperlconf/act/deploy
docker compose --project-directory /home/sciperlconf/act/deploy build act
```

Only after the image build succeeds (activation verifies the running code):

```bash
docker compose --project-directory /home/sciperlconf/act/deploy up -d --no-deps --force-recreate act
perl scripts/setup-proposals.pl /home/sciperlconf/act/deploy --activate
./scripts/apply-theme.sh /home/sciperlconf/act/deploy conference
```

Helpers print backup paths. No other service needs rebuilding. The activation marker enables future theme applications to refresh the form after verifying that the matching handler is running; without it, theme-only deployments retain the upstream form. New choices are 30 and 55 minutes, plus native lightning talks. Existing assigned lengths remain intact. Previously saved custom length requests are retained in the proposal metadata.

Check a proposal and edit it as both speaker and organizer. Verify saved answers, ordinary comments, assigned duration and organizer track assignment. Organizer CSV export also contains the metadata in Comments. Organizer notification emails include the comment details; configure recipients accordingly. No production test submissions are made by the development tests.

## Rollback

Remove the deploy directory's .pcc-proposals-enabled marker. Restore the conference configuration and template from the printed backups; remove the custom actdocs/templates/talk/add if no previous override existed. Restore the previous handler source or image and recreate only act. Saved proposal details remain in Comments. Do not delete database data.

## Development

Run prove -v tests/proposals.t tests/proposal-handler.t. Handler tests require ACT_REFERENCE_LIB pointing to the pinned upstream lib directory (the development VM defaults to /opt/pcc-browser/act-reference/lib), DateTime, Email::Valid, and Text::Diff. They exercise the actual handler and form validator with isolated storage/template doubles. Metadata tests cover round trips and invalid inputs. Browser checks use Perl Playwright against a local preview.

The handler override is based on upstream Act commit 9af60d83390335bdbaeebaa2eb6bc44aa75ecfde. Compare it with upstream when upgrading. No upstream fork is required, but this override is an application customization to maintain.

To reproduce browser fixtures, run perl tests/render-proposals.pl OUTPUT_DIRECTORY, serve that directory locally on port 8765, and run tests/proposal-browser.pl with the Perl Playwright environment. The renderer uses pinned upstream templates and synthetic data, not production accounts. Derived ACT handler/template licensing is included under licenses/act/.

## Rooms

ACT manages room names in the conference actdocs/conf/act.ini file under [rooms], not in a dedicated web administration page. The proposal form omits the Room selector. New proposals automatically use the only configured room when there is exactly one; existing assignments are preserved.

To reduce the three starter rooms to one Main program room, stage with perl scripts/setup-proposals.pl /home/sciperlconf/act/deploy --single-room, then follow the normal build/recreate/activate steps above. This retains the first configured room code and checks existing talk and event assignments before removing the other codes from the active list. It refuses to proceed if another room is still used. No database rows are migrated or removed. Backups include the previous configuration.
