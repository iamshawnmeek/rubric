#!/usr/bin/env python3
"""A local SMTP catcher for the email flow test: writes every message it
receives to <dir>/<n>.eml and never relays anything.

    tool/email/smtp_sink.py <port> <dir>

Plain SMTP only (no STARTTLS), so the server under test needs
SMTP_ALLOW_INSECURE=true, which emailConfigFrom honours only in development.
Python's smtpd module is gone (3.12), and nothing here is worth a dependency.
"""
import os, socketserver, sys

port, out = int(sys.argv[1]), sys.argv[2]
os.makedirs(out, exist_ok=True)


class Session(socketserver.StreamRequestHandler):
    def say(self, line):
        self.wfile.write((line + "\r\n").encode())

    def handle(self):
        self.say("220 rubric-sink ESMTP")
        while True:
            line = self.rfile.readline()
            if not line:
                return
            verb = line.decode(errors="replace").strip().split(" ")[0].upper()
            if verb in ("EHLO", "HELO"):
                self.say("250-rubric-sink")
                self.say("250 AUTH PLAIN LOGIN")
            elif verb == "AUTH":
                # Accept any credentials; answer LOGIN's two prompts.
                if "LOGIN" in line.decode().upper() and len(line.split()) == 2:
                    self.say("334 VXNlcm5hbWU6"); self.rfile.readline()
                    self.say("334 UGFzc3dvcmQ6"); self.rfile.readline()
                self.say("235 ok")
            elif verb in ("MAIL", "RCPT", "RSET", "NOOP"):
                self.say("250 ok")
            elif verb == "DATA":
                self.say("354 end with <CRLF>.<CRLF>")
                body = []
                while True:
                    l = self.rfile.readline()
                    if l in (b".\r\n", b".\n", b""):
                        break
                    body.append(l[1:] if l.startswith(b"..") else l)
                n = len(os.listdir(out))
                tmp = os.path.join(out, f".{n}.tmp")
                with open(tmp, "wb") as f:
                    f.writelines(body)
                os.rename(tmp, os.path.join(out, f"{n}.eml"))
                self.say("250 queued")
            elif verb == "QUIT":
                self.say("221 bye")
                return
            else:
                self.say("502 not implemented")


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


Server(("127.0.0.1", port), Session).serve_forever()
