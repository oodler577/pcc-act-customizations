# Direct SES SMTP for ACT

ACT sends its existing messages directly to Amazon SES over authenticated,
certificate-verified STARTTLS. There is no Postfix service, relay container,
sendmail command wrapper, or persistent retry queue.

## Install on the ACT server

Pull master. Run the following as the deployment administrator:

```bash
python3 scripts/setup-mail.py /path/to/act/deploy sender@example.org
```

The script asks for:
1. SES SMTP hostname (default email-smtp.us-east-1.amazonaws.com).
2. Dedicated SES SMTP username.
3. SMTP password, entered twice through a hidden prompt.

The credentials are written only to:

```text
DEPLOY_DIRECTORY/secrets/ses-smtp.json
```

The JSON has two fields: username and password. Do not paste real values into
chat, Git, shell command arguments, or a Compose environment block.
The file is mode 0600 and owned by the numeric UID/GID used by the running
Act container, so its non-root process can read the Docker secret mount.

The helper creates a Compose override and copies a small SMTP image build
context into DEPLOY_DIRECTORY/smtp. It updates sender_address and disables
email test redirection in the global and selected conference INI files.
Backups are stored under DEPLOY_DIRECTORY/backups/smtp-before-*.
It does not change the base Compose file, start containers, or send mail.
It refuses existing overrides or credential files; merge/rotation requires
intentional handling. Use --conference ID if the ID is not conference.

Build and activate:

```bash
docker compose --project-directory /path/to/act/deploy build act
docker compose --project-directory /path/to/act/deploy up -d --no-deps --force-recreate act
```

The image extends the existing Act image, adds Email::Sender, IO::Socket::SSL,
Authen::SASL, Net::SMTP, and Email::Address as needed, and installs a small
Act::Email transport adapter. Only Act is recreated; its restart is brief.
OJS, databases, conference files, uploaded files, and Nginx are unaffected.

The generated override sets:

```yaml
SMTP_HOST: email-smtp.us-east-1.amazonaws.com
SMTP_PORT: "587"
ACT_SMTP_FROM: sender@example.org
ACT_SMTP_CONFIG: /run/secrets/ses_smtp
```

Use ordinary docker compose commands from the deployment directory, or
--project-directory as shown. Explicit -f commands must include the generated
override. Legacy docker-compose.yml bases get a matching legacy override name.

## Test delivery

```bash
./scripts/send-test-mail.sh /path/to/act/deploy recipient@example.org
docker compose --project-directory /path/to/act/deploy logs --tail=60 act
```

The test uses Act::Email, not an independent sending path. Choose a recipient
you control. Verify inbox delivery and DKIM/SPF/DMARC results, then test a real
registration confirmation and password reset. SES acceptance does not guarantee
inbox placement. No real SES credentials are available in development, so live
verification must be performed on the deployment server.

SES sender verification, SMTP credentials, and production/sandbox status must
match the region. Sandbox SES accounts restrict unverified recipients.
Configure SES bounce and complaint notifications for ongoing delivery visibility.

## Behavior and failure handling

- Without ACT_SMTP_CONFIG, the original unauthenticated SMTP transport remains.
- With ACT_SMTP_CONFIG, authentication and STARTTLS are mandatory.
- The remote certificate chain and SMTP hostname are verified; no insecure
  fallback is allowed.
- Existing message body and MIME headers are preserved. To/Cc/Bcc addresses
  are used for the SMTP envelope; Bcc headers are removed from the wire copy.
- SMTP envelope sender is ACT_SMTP_FROM; configured ACT From/Sender headers
  are set through the INI files.
- Transport failures throw an error instead of reporting successful delivery.
  Logs show a sanitized failure code, not credentials or message bodies.
- Direct SMTP has no durable retry queue and cannot guarantee exactly-once
  delivery if a connection fails after remote acceptance. It can block the
  request while connecting; the transport timeout is 30 seconds.

The original Act::Email code is from book/Act revision
9af60d83390335bdbaeebaa2eb6bc44aa75ecfde; the only integration change selects
Pcc::SMTP when the private configuration path is set. It is not an
asgs-sendmail fork. It follows the same authenticated TLS SMTP approach.

## Password rotation

On the server, use a hidden prompt and preserve the secret file's ownership:

```bash
python3 - /path/to/act/deploy/secrets/ses-smtp.json <<'PY'
import getpass,json,sys
from pathlib import Path
p=Path(sys.argv[1])
config=json.loads(p.read_text())
config["username"]=input("New SMTP username: ").strip()
first=getpass.getpass("New SMTP password: ")
if first != getpass.getpass("Confirm password: "):
    raise SystemExit("Passwords did not match; no changes made")
if not config["username"] or not first or any(c in config["username"]+first for c in "\r\n\x00"):
    raise SystemExit("Invalid credentials; no changes made")
config["password"]=first
with p.open("w") as f: json.dump(config,f);f.write("\n")
p.chmod(0o600)
PY
docker compose --project-directory /path/to/act/deploy restart act
```

The secret is loaded at application startup. Never display it in logs or
commit it. A dedicated SMTP IAM credential set should be scoped to this app.

## Rollback

Move the generated compose.override.yml (or legacy equivalent) out of the
deployment directory. Restore conf/act.ini and the conference act.ini from
the printed smtp-before backup, then recreate only Act using its base image.
Keep the credential file private. This returns to the pre-install mail setup;
it does not configure an alternative delivery service.

## Development tests

```bash
docker build --build-arg ACT_BASE_IMAGE=perl:5.40-bookworm \
  -t pcc-act-smtp-integration deploy/smtp
python3 tests/smtp-integration.py
```

The test runner needs aiosmtpd, Docker, and openssl and runs as root on an
isolated development host with the default Docker bridge and port 587 free
on that bridge interface. All credentials and recipients are synthetic.
It verifies trusted TLS/AUTH delivery, recipient/header preservation,
certificate rejection, authentication failure, and private-file enforcement.

References:
- https://docs.aws.amazon.com/ses/latest/dg/smtp-credentials.html
- https://docs.aws.amazon.com/ses/latest/dg/smtp-connect.html
- https://metacpan.org/pod/Email::Sender::Transport::SMTP
