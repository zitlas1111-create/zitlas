"""
ZITLAS — Support Routes

POST /api/support/contact
  Accepts a support request and emails it to zitlas1111@gmail.com via SMTP.
  Reads credentials from environment:
    SUPPORT_EMAIL          sender address
    SUPPORT_EMAIL_PASSWORD sender app-password / SMTP password
"""

import asyncio
import os
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, EmailStr, Field, field_validator

router = APIRouter()

RECIPIENT = "zitlas1111@gmail.com"
SMTP_HOST = "smtp.gmail.com"
SMTP_PORT = 587


# ── Request model ─────────────────────────────────────────────────────────────

class ContactRequest(BaseModel):
    name:     str  = Field(..., min_length=1,  max_length=120)
    email:    EmailStr
    subject:  str  = Field(..., min_length=1,  max_length=200)
    category: str  = Field(..., min_length=1,  max_length=100)
    message:  str  = Field(..., min_length=20, max_length=5000)

    @field_validator("name", "subject", "category", "message", mode="before")
    @classmethod
    def strip_whitespace(cls, v: str) -> str:
        return v.strip() if isinstance(v, str) else v


# ── Email builder ─────────────────────────────────────────────────────────────

def _build_email(data: ContactRequest, sender: str) -> MIMEMultipart:
    msg = MIMEMultipart("alternative")
    msg["Subject"] = f"[ZITLAS Support] {data.subject}"
    msg["From"]    = sender
    msg["To"]      = RECIPIENT
    msg["Reply-To"] = data.email

    plain = (
        "New Support Request\n"
        "===================\n\n"
        f"Name:     {data.name}\n"
        f"Email:    {data.email}\n"
        f"Category: {data.category}\n"
        f"Subject:  {data.subject}\n\n"
        f"Message:\n{data.message}\n"
    )

    html = f"""\
<html>
<body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
             background:#0A0A0A;color:#FFFFFF;margin:0;padding:32px 16px;">
  <div style="max-width:560px;margin:0 auto;background:#141414;
              border:1px solid #262626;border-radius:16px;overflow:hidden;">

    <div style="background:#FF8A00;padding:20px 28px;">
      <h1 style="margin:0;font-size:20px;font-weight:800;color:#fff;
                 letter-spacing:1px;">ZITLAS</h1>
      <p style="margin:4px 0 0;font-size:13px;color:rgba(255,255,255,0.85);">
        New Support Request
      </p>
    </div>

    <div style="padding:24px 28px;">

      <table style="width:100%;border-collapse:collapse;">
        <tr>
          <td style="padding:10px 0;border-bottom:1px solid #1e1e1e;
                     font-size:12px;font-weight:600;color:#666;
                     text-transform:uppercase;letter-spacing:0.5px;width:110px;">
            Name
          </td>
          <td style="padding:10px 0;border-bottom:1px solid #1e1e1e;
                     font-size:14px;color:#FFFFFF;">
            {data.name}
          </td>
        </tr>
        <tr>
          <td style="padding:10px 0;border-bottom:1px solid #1e1e1e;
                     font-size:12px;font-weight:600;color:#666;
                     text-transform:uppercase;letter-spacing:0.5px;">
            Email
          </td>
          <td style="padding:10px 0;border-bottom:1px solid #1e1e1e;
                     font-size:14px;color:#FF8A00;">
            <a href="mailto:{data.email}"
               style="color:#FF8A00;text-decoration:none;">{data.email}</a>
          </td>
        </tr>
        <tr>
          <td style="padding:10px 0;border-bottom:1px solid #1e1e1e;
                     font-size:12px;font-weight:600;color:#666;
                     text-transform:uppercase;letter-spacing:0.5px;">
            Category
          </td>
          <td style="padding:10px 0;border-bottom:1px solid #1e1e1e;
                     font-size:14px;color:#FFFFFF;">
            {data.category}
          </td>
        </tr>
        <tr>
          <td style="padding:10px 0;border-bottom:1px solid #1e1e1e;
                     font-size:12px;font-weight:600;color:#666;
                     text-transform:uppercase;letter-spacing:0.5px;">
            Subject
          </td>
          <td style="padding:10px 0;border-bottom:1px solid #1e1e1e;
                     font-size:14px;color:#FFFFFF;">
            {data.subject}
          </td>
        </tr>
      </table>

      <div style="margin-top:20px;">
        <p style="font-size:12px;font-weight:600;color:#666;
                  text-transform:uppercase;letter-spacing:0.5px;margin:0 0 10px;">
          Message
        </p>
        <div style="background:#0f0f0f;border:1px solid #2a2a2a;
                    border-radius:10px;padding:16px;font-size:14px;
                    color:#B5B5B5;line-height:1.7;white-space:pre-wrap;">
{data.message}
        </div>
      </div>

    </div>

    <div style="padding:16px 28px;border-top:1px solid #1e1e1e;
                font-size:11.5px;color:#444;text-align:center;">
      Sent via ZITLAS Help &amp; Support — reply to this email to respond to {data.name}
    </div>

  </div>
</body>
</html>
"""

    msg.attach(MIMEText(plain, "plain"))
    msg.attach(MIMEText(html,  "html"))
    return msg


# ── SMTP send (runs in thread pool to avoid blocking the event loop) ──────────

def _send_sync(data: ContactRequest) -> None:
    sender   = os.environ.get("SUPPORT_EMAIL", "")
    password = os.environ.get("SUPPORT_EMAIL_PASSWORD", "")

    if not sender or not password:
        raise RuntimeError(
            "SUPPORT_EMAIL or SUPPORT_EMAIL_PASSWORD not set in environment."
        )

    msg = _build_email(data, sender)

    with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
        server.ehlo()
        server.starttls()
        server.ehlo()
        server.login(sender, password)
        server.sendmail(sender, RECIPIENT, msg.as_string())


# ── Route ─────────────────────────────────────────────────────────────────────

@router.post("/contact")
async def contact_support(data: ContactRequest):
    try:
        await asyncio.to_thread(_send_sync, data)
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc))
    except smtplib.SMTPAuthenticationError:
        raise HTTPException(
            status_code=503,
            detail="Email service authentication failed. Please contact us directly at zitlas1111@gmail.com",
        )
    except Exception:
        raise HTTPException(
            status_code=503,
            detail="Failed to send email. Please try again later.",
        )

    return {"success": True, "message": "Your message has been sent to Team ZITLAS."}
