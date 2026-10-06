#!/usr/bin/env python3
"""Generates Rubric's account email templates from one layout.

    tool/email/templates.py           # write server/lib/src/email_templates/
    tool/email/templates.py --check   # fail if the committed files differ

zonai renders `lib/src/email_templates/<name>.html` with Mustache ({{var}} is
HTML-escaped). Rubric signs in with a password only, so the two templates it
can send are the ones here; zonai's magic-link, OTP and change-email
templates are not used and so not shipped.

Email HTML is its own dialect: tables for layout, every style inline, no web
fonts, no CSS variables, nothing that needs JavaScript. The colours are the
design system's (lib/design_system/colors.dart). The body is light because
mail clients that force a dark mode invert light designs far better than they
invert dark ones; the brand's dark purple carries the header band and the
orange carries the one button.
"""
import os
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "server", "lib", "src", "email_templates")

SECONDARY = "#2F035F"  # header band, headings
PRIMARY_DARK = "#6E27BC"  # links
ACCENT = "#FFAD00"  # the button
INK = "#1F1530"  # body text
MUTED = "#6B5E80"  # secondary text
PAGE = "#F4F0FA"  # around the card
FONT = "'Avenir Next', Avenir, 'Segoe UI', Helvetica, Arial, sans-serif"
SITE = "https://yourrubric.com"

PREHEADER = """{{#preheader}}
<div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:transparent;opacity:0;">{{preheader}}""" + (
    "&#847;&zwnj;&nbsp;&#8203;" * 20
) + """</div>
{{/preheader}}"""


def button(url_var: str, label: str) -> str:
    """A 'bulletproof' button: a padded table cell, so it renders in Outlook
    too, where a styled <a> loses its padding."""
    return f"""<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:28px 0;">
  <tr>
    <td align="center" bgcolor="{ACCENT}" style="border-radius:10px;">
      <a href="{{{{{url_var}}}}}" target="_blank" style="display:inline-block;padding:14px 28px;font-family:{FONT};font-size:16px;font-weight:700;color:{SECONDARY};text-decoration:none;border-radius:10px;">{label}</a>
    </td>
  </tr>
</table>"""


def fallback(url_var: str) -> str:
    return f"""<p style="margin:0 0 6px;font-size:13px;line-height:20px;color:{MUTED};">If the button doesn&rsquo;t work, paste this link into your browser:</p>
<p style="margin:0;font-size:13px;line-height:20px;word-break:break-all;"><a href="{{{{{url_var}}}}}" style="color:{PRIMARY_DARK};">{{{{{url_var}}}}}</a></p>"""


def page(title: str, body: str, footer: str) -> str:
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<title>{title}</title>
</head>
<body style="margin:0;padding:0;background:{PAGE};">
{PREHEADER}
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:{PAGE};">
  <tr>
    <td align="center" style="padding:32px 16px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;background:#FFFFFF;border-radius:10px;overflow:hidden;">
        <tr>
          <td style="background:{SECONDARY};padding:22px 32px;">
            <img src="{SITE}/assets/img/email-icon.png" width="36" height="36" alt="" style="vertical-align:middle;border-radius:8px;border:0;">
            <span style="vertical-align:middle;margin-left:10px;font-family:{FONT};font-size:20px;font-weight:700;color:#FFFFFF;">Rubric</span>
          </td>
        </tr>
        <tr>
          <td style="padding:32px;font-family:{FONT};font-size:16px;line-height:24px;color:{INK};">
{body}
          </td>
        </tr>
        <tr>
          <td style="padding:20px 32px 28px;border-top:1px solid #ECE6F5;font-family:{FONT};font-size:12px;line-height:18px;color:{MUTED};">
            {footer}<br>
            Rubric &middot; <a href="{SITE}" style="color:{MUTED};">yourrubric.com</a> &middot; <a href="{SITE}/privacy.html" style="color:{MUTED};">Privacy</a>
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>
</body>
</html>
"""


def heading(text: str) -> str:
    return f'<h1 style="margin:0 0 16px;font-size:22px;line-height:30px;color:{SECONDARY};">{text}</h1>'


def para(text: str) -> str:
    return f'<p style="margin:0 0 16px;">{text}</p>'


TEMPLATES = {
    "verify_email": page(
        "Confirm your email",
        "\n".join([
            heading("Confirm your email"),
            para("Hi{{#name}} {{name}}{{/name}},"),
            para("Tap the button to confirm <strong>{{email}}</strong> for your Rubric account. "
                 "It&rsquo;s how we know a password reset reaches you."),
            button("verificationUrl", "Confirm my email"),
            para("This link expires in {{expiresIn}}."),
            fallback("verificationUrl"),
        ]),
        "You&rsquo;re getting this because this address was used to create a Rubric account. "
        "If that wasn&rsquo;t you, ignore it and nothing changes.",
    ),
    "password_reset": page(
        "Reset your password",
        "\n".join([
            heading("Reset your password"),
            para("Hi{{#name}} {{name}}{{/name}},"),
            para("Someone asked to reset the password for your Rubric account. "
                 "Tap the button to choose a new one."),
            button("passwordResetUrl", "Choose a new password"),
            para("This link expires in {{expiresIn}} and works once."),
            fallback("passwordResetUrl"),
        ]),
        "If you didn&rsquo;t ask for this, ignore it: your password stays the same.",
    ),
}


def main() -> int:
    check = "--check" in sys.argv[1:]
    stale = []
    os.makedirs(OUT, exist_ok=True)
    for name, html in TEMPLATES.items():
        path = os.path.join(OUT, f"{name}.html")
        current = open(path).read() if os.path.exists(path) else None
        if current == html:
            continue
        if check:
            stale.append(path)
        else:
            with open(path, "w") as f:
                f.write(html)
            print(f"templates: wrote {os.path.relpath(path, ROOT)}")
    extra = sorted(set(os.listdir(OUT)) - {f"{n}.html" for n in TEMPLATES})
    if extra:
        print(f"templates: not generated here, remove or add them: {extra}", file=sys.stderr)
        return 1
    if stale:
        print("templates: out of date, run tool/email/templates.py:", *stale, sep="\n  ", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
