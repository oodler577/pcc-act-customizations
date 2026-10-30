#!/usr/bin/env python3
"""Synthetic SMTP integration check; requires Docker, openssl, and aiosmtpd."""
import argparse,json,os,subprocess as sp,sys,tempfile,time
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument("--image",default="pcc-act-smtp-integration")
a=p.parse_args()
def run(*args):
    return sp.run(args,check=True,text=True,capture_output=True).stdout
server=None
with tempfile.TemporaryDirectory(prefix="pcc-direct-smtp-test-") as tmp:
    d=Path(tmp)
    run("openssl","req","-x509","-newkey","rsa:2048","-nodes","-days","1","-subj","/CN=smtp.integration.test","-addext","subjectAltName=DNS:smtp.integration.test","-keyout",str(d/"key.pem"),"-out",str(d/"cert.pem"))
    (d/"ca.pem").write_bytes(Path("/etc/ssl/certs/ca-certificates.crt").read_bytes()+(d/"cert.pem").read_bytes())
    gateway=json.loads(run("docker","network","inspect","bridge"))[0]["IPAM"]["Config"][0]["Gateway"]
    (d/"server.py").write_text("""
import ssl,time,sys,json
from pathlib import Path
from aiosmtpd.controller import Controller
from aiosmtpd.smtp import AuthResult,LoginPassword
d=Path(sys.argv[1])
def auth(server,session,envelope,mechanism,data):
    ok=isinstance(data,LoginPassword) and data.login==b'integration-user' and data.password==b'not-a-real-smtp-password'
    return AuthResult(success=ok,handled=False)
class Handler:
    async def handle_DATA(self,server,session,envelope):
        (d/'delivered.eml').write_bytes(envelope.original_content)
        (d/'envelope.json').write_text(json.dumps(dict(sender=envelope.mail_from,recipients=envelope.rcpt_tos,authenticated=session.authenticated)))
        return '250 2.0.0 synthetic test accepted'
ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);ctx.load_cert_chain(d/'cert.pem',d/'key.pem')
c=Controller(Handler(),hostname=sys.argv[2],port=587,tls_context=ctx,require_starttls=True,auth_required=True,authenticator=auth)
c.start()
(d/'ready').touch()
while True:time.sleep(1)
""")
    (d/"send.pl").write_text("""
use strict;use warnings;use Pcc::SMTP;use Email::Simple;
my $smtp=Pcc::SMTP->new(config_file=>'/run/secrets/ses_smtp');
my $email=Email::Simple->create(header=>[
    From=>'sender@example.invalid',
    To=>'"Primary Person" <recipient@example.invalid>',
    Cc=>'copy@example.invalid',
    Bcc=>'hidden@example.invalid, recipient@example.invalid',
    Subject=>'Synthetic direct SMTP test',
    'Content-Type'=>'text/plain; charset=UTF-8',
],body=>"Synthetic direct SMTP body.\r\n");
$smtp->send($email);
die "Original Bcc changed" unless $email->header('Bcc');
print "SMTP submission accepted\\n";
""")
    secret=d/"credentials.json"
    def credentials(password):
        secret.write_text(json.dumps(dict(username="integration-user",password=password)))
        secret.chmod(0o600);os.chown(secret,10001,10001)
    def send(trust=False):
        args=["docker","run","--rm","--user","10001:10001","--add-host","smtp.integration.test:host-gateway",
              "-e","SMTP_HOST=smtp.integration.test","-e","SMTP_PORT=587","-e","ACT_SMTP_FROM=sender@example.invalid",
              "-v",str(secret)+":/run/secrets/ses_smtp:ro","-v",str(d/"send.pl")+":/tmp/send.pl:ro"]
        if trust:args+=["-v",str(d/"ca.pem")+":/etc/ssl/certs/ca-certificates.crt:ro"]
        args+=[a.image,"perl","-I/opt/act/lib","/tmp/send.pl"]
        return sp.run(args,text=True,capture_output=True,timeout=50)
    try:
        server=sp.Popen([sys.executable,str(d/"server.py"),str(d),gateway],stdout=sp.DEVNULL,stderr=sp.DEVNULL)
        for _ in range(40):
            if (d/"ready").exists():break
            if server.poll() is not None:raise RuntimeError("Synthetic SMTP server failed")
            time.sleep(.25)
        credentials("not-a-real-smtp-password")
        result=send(False)
        assert result.returncode!=0,result.stdout
        assert not (d/"delivered.eml").exists()
        assert "not-a-real-smtp-password" not in result.stderr
        print("PASS untrusted TLS certificate rejected; no secret in error output",flush=True)
        result=send(True)
        assert result.returncode==0,result.stderr
        env=json.loads((d/"envelope.json").read_text())
        assert env["authenticated"] and env["sender"]=="sender@example.invalid",env
        assert set(env["recipients"])=={"recipient@example.invalid","copy@example.invalid","hidden@example.invalid"},env
        message=(d/"delivered.eml").read_text()
        assert "\nBcc:" not in message
        assert "Synthetic direct SMTP body." in message
        print("PASS verified STARTTLS and AUTH; To/Cc/Bcc recipients preserved, Bcc hidden",flush=True)
        (d/"delivered.eml").unlink()
        credentials("wrong-password-for-negative-test")
        result=send(True)
        assert result.returncode!=0
        assert not (d/"delivered.eml").exists()
        assert "wrong-password-for-negative-test" not in result.stderr
        print("PASS authentication failure is reported; no silent success or password output",flush=True)
        secret.chmod(0o644)
        result=send(True)
        assert result.returncode!=0 and "must be private" in result.stderr
        print("PASS world-readable credential file rejected",flush=True)
    finally:
        if server:server.terminate();server.wait(timeout=10)
