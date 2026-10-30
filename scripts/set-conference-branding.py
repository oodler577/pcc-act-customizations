#!/usr/bin/env python3
"""Set conference/email branding without reading or changing SMTP credentials."""
import argparse,json,os,re,shutil,tempfile
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument("deployment",type=Path)
p.add_argument("--name",default="Perl Community Conference")
p.add_argument("--conference",default="conference")
a=p.parse_args()
if os.geteuid()!=0:raise SystemExit("Run as root")
if not a.name.strip() or re.search(r"[\r\n\x00]",a.name):raise SystemExit("Invalid display name")
if not re.fullmatch(r"[A-Za-z0-9_-]+",a.conference):raise SystemExit("Invalid conference ID")
d=a.deployment.resolve(strict=True)
repo=Path(__file__).resolve().parent.parent
conf=d/"conferences"/a.conference/"actdocs/conf/act.ini"
overrides=[d/n for n in ("compose.override.yml","compose.override.yaml","docker-compose.override.yml","docker-compose.override.yaml") if (d/n).exists()]
if len(overrides)!=1 or not conf.is_file() or not (d/"smtp").is_dir():
    raise SystemExit("Expected the installed direct SMTP setup and conference configuration")
override=overrides[0]
text=conf.read_text()
match=re.search(r"(?ms)^\[general\][^\S\n]*\n(.*?)(?=^\[|\Z)",text)
if not match:raise SystemExit("Missing general conference section")
section=match.group(1)
section,count=re.subn(r"(?m)^name(?:_[a-zA-Z_]+)?\s*=.*$",lambda m:"name_en = "+a.name if m.group().split("=")[0].strip()=="name_en" else m.group().split("=")[0].strip()+" = "+a.name,section)
if not re.search(r"(?m)^name_en\s*=",section):section+="\nname_en = "+a.name+"\n"
updated=text[:match.start(1)]+section+text[match.end(1):]
overlay=override.read_text()
setting="      ACT_SMTP_FROM_NAME: "+json.dumps(a.name)
if re.search(r"(?m)^      ACT_SMTP_FROM_NAME:",overlay):
    overlay=re.sub(r"(?m)^      ACT_SMTP_FROM_NAME:.*$",lambda m:setting,overlay)
else:
    overlay,count=re.subn(r"(?m)^(      ACT_SMTP_FROM:.*)$",lambda m:m.group(1)+"\n"+setting,overlay)
    if count!=1:raise SystemExit("Unrecognized SMTP override; no changes made")
os.umask(0o077)
(d/"backups").mkdir(exist_ok=True)
backup=Path(tempfile.mkdtemp(prefix="branding-before-",dir=d/"backups"))
for f in (conf,override):
    target=backup/f.relative_to(d);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,target)
conf.write_text(updated)
override.write_text(overlay)
shutil.copytree(repo/"deploy/smtp",d/"smtp",dirs_exist_ok=True)
print("Conference name and SMTP sender name:",a.name)
print("Configuration backup:",backup)
print("SMTP credentials were not read or changed.")
print("Apply the theme, rebuild Act, and recreate its container as documented.")
