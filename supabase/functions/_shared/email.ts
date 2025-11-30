// Email sending utilities using Resend API

interface EmailOptions {
  to: string
  subject: string
  html: string
  from?: string
}

interface ResendResponse {
  id?: string
  error?: {
    message: string
    statusCode: number
  }
}

export async function sendEmail(options: EmailOptions): Promise<{ success: boolean; error?: string }> {
  const resendApiKey = Deno.env.get('RESEND_API_KEY')

  if (!resendApiKey) {
    console.error('RESEND_API_KEY not configured')
    return { success: false, error: 'Email service not configured' }
  }

  const fromEmail = options.from || Deno.env.get('EMAIL_FROM') || 'NextLean Scan <noreply@nextleanscan.com>'

  console.log('Sending email via Resend:', { to: options.to, from: fromEmail, subject: options.subject })

  try {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${resendApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: fromEmail,
        to: options.to,
        subject: options.subject,
        html: options.html,
      }),
    })

    const data: ResendResponse = await response.json()

    console.log('Resend API response:', { status: response.status, data })

    if (!response.ok || data.error) {
      console.error('Resend error:', JSON.stringify(data))
      return { success: false, error: data.error?.message || `Resend API error (${response.status})` }
    }

    console.log('Email sent successfully, ID:', data.id)
    return { success: true }
  } catch (error) {
    console.error('Email send error:', error)
    return { success: false, error: `Failed to send email: ${error}` }
  }
}

// Generate invitation email HTML
export function generateInvitationEmailHtml(options: {
  showroomName: string
  inviteeName: string | null
  invitationLink: string
  expiresAt: string
  customMessage?: string | null
  logoUrl?: string | null
  primaryColor?: string
}): string {
  const {
    showroomName,
    inviteeName,
    invitationLink,
    expiresAt,
    customMessage,
    logoUrl,
    primaryColor = '#2563EB',
  } = options

  const greeting = inviteeName ? `Hello ${inviteeName}` : 'Hello'
  const expiresDate = new Date(expiresAt).toLocaleDateString('en-US', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  })

  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>You're Invited to Manage ${showroomName}</title>
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #f3f4f6;">
  <table role="presentation" style="width: 100%; border-collapse: collapse;">
    <tr>
      <td align="center" style="padding: 40px 20px;">
        <table role="presentation" style="width: 100%; max-width: 600px; border-collapse: collapse; background-color: #ffffff; border-radius: 12px; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);">
          <!-- Header -->
          <tr>
            <td style="padding: 40px 40px 20px; text-align: center; border-bottom: 1px solid #e5e7eb;">
              ${logoUrl ? `<img src="${logoUrl}" alt="${showroomName}" style="max-height: 60px; max-width: 200px; margin-bottom: 16px;">` : ''}
              <h1 style="margin: 0; font-size: 24px; font-weight: 700; color: #111827;">
                You're Invited!
              </h1>
            </td>
          </tr>

          <!-- Body -->
          <tr>
            <td style="padding: 40px;">
              <p style="margin: 0 0 20px; font-size: 16px; line-height: 1.6; color: #374151;">
                ${greeting},
              </p>
              <p style="margin: 0 0 20px; font-size: 16px; line-height: 1.6; color: #374151;">
                You've been invited to manage <strong style="color: ${primaryColor};">${showroomName}</strong> on NextLean Scan.
                This platform will allow you to view 3D room scans, manage your product catalog, and connect with customers.
              </p>
              ${customMessage ? `
              <div style="margin: 0 0 24px; padding: 16px; background-color: #f9fafb; border-radius: 8px; border-left: 4px solid ${primaryColor};">
                <p style="margin: 0; font-size: 14px; line-height: 1.6; color: #4b5563; font-style: italic;">
                  "${customMessage}"
                </p>
              </div>
              ` : ''}
              <p style="margin: 0 0 32px; font-size: 16px; line-height: 1.6; color: #374151;">
                Click the button below to set up your account and get started:
              </p>

              <!-- CTA Button -->
              <table role="presentation" style="width: 100%; border-collapse: collapse;">
                <tr>
                  <td align="center">
                    <a href="${invitationLink}"
                       style="display: inline-block; padding: 16px 32px; background-color: ${primaryColor}; color: #ffffff; text-decoration: none; font-size: 16px; font-weight: 600; border-radius: 8px; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);">
                      Accept Invitation
                    </a>
                  </td>
                </tr>
              </table>

              <p style="margin: 32px 0 0; font-size: 14px; line-height: 1.6; color: #6b7280;">
                This invitation expires on <strong>${expiresDate}</strong>. If you didn't expect this invitation, you can safely ignore this email.
              </p>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="padding: 24px 40px; background-color: #f9fafb; border-radius: 0 0 12px 12px; border-top: 1px solid #e5e7eb;">
              <p style="margin: 0 0 8px; font-size: 12px; color: #9ca3af; text-align: center;">
                This email was sent by NextLean Scan
              </p>
              <p style="margin: 0; font-size: 12px; color: #9ca3af; text-align: center;">
                If the button doesn't work, copy and paste this link into your browser:<br>
                <a href="${invitationLink}" style="color: ${primaryColor}; word-break: break-all;">${invitationLink}</a>
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
`
}
