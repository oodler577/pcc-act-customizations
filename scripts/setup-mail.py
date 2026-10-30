#!/usr/bin/env python3
"""Configure direct authenticated SES SMTP; password is entered locally."""
import argparse, getpass, json, os, re, shutil, subprocess, tempfile
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument("deployment", type=Path)
p.add_argument("sender")
p.add_argument("--conference", default="conference")
a = p.parse_args()
if os.geteuid() != 0: raise SystemExit("Run as root so the secret can be owned by the Act container UID")
d = a.deployment.resolve(strict=True)
repo = Path(__file__).resolve().parent.parent
if repo == d or repo in d.parents:
    raise SystemExit("Deployment and secrets must be outside this repository")
if not re.fullmatch(r"[A-Za-z0-9_-]+", a.conference):
    raise SystemExit("Invalid conference ID")
if not re.fullmatch(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", a.sender):
    raise SystemExit("Invalid sender")
base = [x for x in ("compose.yml","compose.yaml","docker-compose.yml","docker-compose.yaml") if (d/x).exists()]
if len(base) != 1: raise SystemExit("Expected exactly one base Compose file")
override = d/("docker-compose.override.yml" if base[0].startswith("docker-") else "compose.override.yml")
if any((d/x).exists() for x in ("compose.override.yml","compose.override.yaml","docker-compose.override.yml","docker-compose.override.yaml")):
    raise SystemExit("Existing Compose override requires manual merge; no changes made")
if os.environ.get("COMPOSE_FILE"): raise SystemExit("Unset COMPOSE_FILE first")
compose = ["docker","compose","--project-directory",str(d)]
resolved = json.loads(subprocess.check_output(compose+["config","--format","json"],text=True))
image = resolved["services"]["act"]["image"]
# Secret mounts retain host ownership on local Docker Compose.
uid = int(subprocess.check_output(compose+["exec","-T","act","id","-u"],text=True).strip())
gid = int(subprocess.check_output(compose+["exec","-T","act","id","-g"],text=True).strip())
configs = [d/"conf/act.ini",d/"conferences"/a.conference/"actdocs/conf/act.ini"]
for f in configs:
    if not f.is_file(): raise SystemExit("Missing configuration: "+str(f))
secret = d/"secrets/ses-smtp.json"
if secret.exists(): raise SystemExit("SMTP credential file already exists; stopping")
if (d/"smtp").exists(): raise SystemExit("SMTP build directory already exists; stopping")
host = input("SES SMTP host [email-smtp.us-east-1.amazonaws.com]: ").strip() or "email-smtp.us-east-1.amazonaws.com"
if not re.fullmatch(r"email-smtp\.[a-z0-9-]+\.amazonaws\.com",host):
    raise SystemExit("Expected a standard SES SMTP hostname")
username = input("SES SMTP username: ").strip()
password = getpass.getpass("SES SMTP password (hidden): ")
if password != getpass.getpass("Confirm SMTP password: "): raise SystemExit("Passwords did not match")
if not username or not password or re.search(r"[\r\n\x00]",username+password):
    raise SystemExit("Missing or invalid SMTP credentials")
os.umask(0o077)
(d/"backups").mkdir(exist_ok=True)
backup = Path(tempfile.mkdtemp(prefix="smtp-before-",dir=d/"backups"))
for f in configs:
    target=backup/f.relative_to(d);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,target)
(d/"secrets").mkdir(mode=0o700,exist_ok=True)
def update_email(f):
    text=f.read_text()
    values=dict(sender_address=a.sender,test="0",hostname=host,port="587")
    m=re.search(r"(?ms)^\[email\][^\S\n]*\n(.*?)(?=^\[|\Z)",text)
    if m:
        section=m.group(1)
        for k,v in values.items():
            pattern=r"(?m)^"+k+r"\s*=.*$"
            section=re.sub(pattern,k+" = "+v,section) if re.search(pattern,section) else section+"\n"+k+" = "+v+"\n"
        text=text[:m.start(1)]+section+text[m.end(1):]
    else: text+="\n[email]\n"+"".join(k+" = "+v+"\n" for k,v in values.items())
    f.write_text(text)
try:
    # Exclusive creation; no password appears in arguments, environment, or output.
    fd=os.open(secret,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,"w") as fh: json.dump(dict(username=username,password=password),fh);fh.write("\n")
    os.chown(secret,uid,gid)
    shutil.copytree(repo/"deploy/smtp",d/"smtp",dirs_exist_ok=True)
    for f in configs: update_email(f)
    override.write_text("""# Managed by pcc-act-styles direct SMTP setup.
services:
  act:
    image: pcc-act-smtp:local
    build:
      context: ./smtp
      args:
        ACT_BASE_IMAGE: """+json.dumps(image)+"""
    environment:
      SMTP_HOST: """+json.dumps(host)+"""
      SMTP_PORT: "587"
      ACT_SMTP_FROM: """+json.dumps(a.sender)+"""
      ACT_SMTP_CONFIG: /run/secrets/ses_smtp
    secrets:
      - ses_smtp
secrets:
  ses_smtp:
    file: ./secrets/ses-smtp.json
""")
    subprocess.run(compose+["config","--quiet"],check=True)
except BaseException:
    for f in configs: shutil.copy2(backup/f.relative_to(d),f)
    override.unlink(missing_ok=True);secret.unlink(missing_ok=True)
    shutil.rmtree(d/"smtp",ignore_errors=True)
    raise
print("SMTP credentials saved privately to:",secret)
print("Configuration backup:",backup)
print("No containers changed and no mail sent.")
print("Next: docker compose --project-directory",str(d),"build act")
print("Then: docker compose --project-directory",str(d),"up -d --no-deps --force-recreate act")
