#!/usr/bin/env python3
"""Configure English-only PCC and stage disabled wiki handlers in the SMTP image."""
import argparse, configparser, datetime, shutil
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('deploy',type=Path);p.add_argument('--conference',default='conference');a=p.parse_args()
r=Path(__file__).resolve().parents[1];d=a.deploy.resolve()
if not a.conference.replace('-','').replace('_','').isalnum():p.error('Invalid conference ID')
c=d/'conferences'/a.conference/'actdocs/conf/act.ini'
if not c.is_file() or not (d/'smtp/Dockerfile').is_file():p.error('Expected an existing PCC deployment with direct SMTP installed')
backup=d/'backups'/('site-before-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f'));backup.mkdir(parents=True,mode=0o700)
shutil.copy2(c,backup/'act.ini')
# Edit only the general language settings; preserve comments and all other config.
s=c.read_text();lines=s.splitlines(keepends=True);inside=False;seen=set();out=[]
import re
for line in lines:
 if re.match(r'^\s*\[',line):
  if inside:
   for key,value in [('languages','en'),('default_language','en')]:
    if key not in seen:out.append(f'{key} = {value}\n')
  inside=bool(re.match(r'^\s*\[general\]\s*$',line));
 if inside:
  m=re.match(r'^\s*(languages|default_language)\s*=',line)
  if m:seen.add(m[1]);line=f'{m[1]} = en\n'
 out.append(line)
if not seen:p.error('General language settings not found; no config changes made')
c.write_text(''.join(out))
for name in ('Wiki.pm','WikiEdit.pm'):
 dest=d/'smtp/lib/Act/Handler'/name;dest.parent.mkdir(parents=True,exist_ok=True)
 if dest.exists():shutil.copy2(dest,backup/name)
 shutil.copy2(r/'deploy/smtp/lib/Act/Handler'/name,dest)
dest=d/'smtp/lib/Act/Middleware/Language.pm'
dest.parent.mkdir(parents=True,exist_ok=True)
if dest.exists():shutil.copy2(dest,backup/'Language.pm')
shutil.copy2(r/'deploy/smtp/lib/Act/Middleware/Language.pm',dest)
print(f'Staged site changes. Configuration backup: {backup}')
print('Next: apply-theme.sh, then docker compose build act and recreate act.')
