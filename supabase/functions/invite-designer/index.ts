import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import { sendEmail } from '../_shared/email.ts'

interface InviteDesignerRequest {
  email: string
  full_name: string
}

interface InviteDesignerResponse {
  success: boolean
  invitation_id?: string
  invitation_link?: string
  error?: string
}

function generateDesignerInvitationEmailHtml(options: {
  designerName: string
  invitationLink: string
  expiresAt: string
}): string {
  const { designerName, invitationLink, expiresAt } = options

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
  <title>You're Invited to Join CabinetScan as a Designer</title>
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #f3f4f6;">
  <table role="presentation" style="width: 100%; border-collapse: collapse;">
    <tr>
      <td align="center" style="padding: 40px 20px;">
        <table role="presentation" style="width: 100%; max-width: 600px; border-collapse: collapse; background-color: #ffffff; border-radius: 12px; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);">
          <!-- Header -->
          <tr>
            <td style="padding: 40px 40px 20px; text-align: center; border-bottom: 1px solid #e5e7eb;">
              <h1 style="margin: 0; font-size: 24px; font-weight: 700; color: #111827;">
                You're Invited!
              </h1>
            </td>
          </tr>

          <!-- Body -->
          <tr>
            <td style="padding: 40px;">
              <p style="margin: 0 0 20px; font-size: 16px; line-height: 1.6; color: #374151;">
                Hello ${designerName},
              </p>
              <p style="margin: 0 0 20px; font-size: 16px; line-height: 1.6; color: #374151;">
                You've been invited to join <strong style="color: #2563EB;">CabinetScan</strong> as a designer.
                You'll be able to accept design requests, deliver floor plans and renderings, and collaborate with showroom customers.
              </p>
              <p style="margin: 0 0 32px; font-size: 16px; line-height: 1.6; color: #374151;">
                Click the button below to set up your account and get started:
              </p>

              <!-- CTA Button -->
              <table role="presentation" style="width: 100%; border-collapse: collapse;">
                <tr>
                  <td align="center">
                    <a href="${invitationLink}"
                       style="display: inline-block; padding: 16px 32px; background-color: #2563EB; color: #ffffff; text-decoration: none; font-size: 16px; font-weight: 600; border-radius: 8px; box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);">
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
                This email was sent by CabinetScan
              </p>
              <p style="margin: 0; font-size: 12px; color: #9ca3af; text-align: center;">
                If the button doesn't work, copy and paste this link into your browser:<br>
                <a href="${invitationLink}" style="color: #2563EB; word-break: break-all;">${invitationLink}</a>
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

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Only allow POST
    if (req.method !== 'POST') {
      return new Response(
        JSON.stringify({ success: false, error: 'Method not allowed' }),
        { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get the authorization header to identify the caller
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify the caller is a super admin
    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)

    if (authError || !user) {
      return new Response(
        JSON.stringify({ success: false, error: 'Invalid authentication' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check if user is super admin
    const { data: admin, error: adminError } = await supabaseAdmin
      .from('admins')
      .select('id')
      .eq('user_id', user.id)
      .eq('is_active', true)
      .single()

    if (adminError || !admin) {
      return new Response(
        JSON.stringify({ success: false, error: 'Only super admins can invite designers' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Parse request body
    const body: InviteDesignerRequest = await req.json()

    // Validate required fields
    if (!body.email) {
      return new Response(
        JSON.stringify({ success: false, error: 'email is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!body.full_name) {
      return new Response(
        JSON.stringify({ success: false, error: 'full_name is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    if (!emailRegex.test(body.email)) {
      return new Response(
        JSON.stringify({ success: false, error: 'Invalid email format' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const emailLower = body.email.toLowerCase()

    // Check if designer already exists
    const { data: existingDesigner } = await supabaseAdmin
      .from('designers')
      .select('id')
      .eq('email', emailLower)
      .single()

    if (existingDesigner) {
      return new Response(
        JSON.stringify({ success: false, error: 'A designer with this email already exists' }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check for existing pending invitation
    const { data: existingInvitation } = await supabaseAdmin
      .from('designer_invitations')
      .select('id, expires_at, accepted_at')
      .eq('email', emailLower)
      .is('accepted_at', null)
      .single()

    if (existingInvitation) {
      if (new Date(existingInvitation.expires_at) > new Date()) {
        return new Response(
          JSON.stringify({
            success: false,
            error: 'A pending invitation already exists for this email',
            invitation_id: existingInvitation.id,
          }),
          { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      // Expired invitation exists - delete it so we can create a new one
      await supabaseAdmin
        .from('designer_invitations')
        .delete()
        .eq('id', existingInvitation.id)
    }

    // Generate token
    const invitationToken = crypto.randomUUID()

    // Calculate expiration (7 days from now)
    const expiresAt = new Date()
    expiresAt.setDate(expiresAt.getDate() + 7)

    // Create invitation record
    const { data: invitation, error: insertError } = await supabaseAdmin
      .from('designer_invitations')
      .insert({
        email: emailLower,
        full_name: body.full_name.trim(),
        token: invitationToken,
        invited_by: admin.id,
        expires_at: expiresAt.toISOString(),
      })
      .select('id')
      .single()

    if (insertError || !invitation) {
      console.error('Failed to create designer invitation:', insertError)
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to create invitation' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Build invitation link
    const dashboardUrl = Deno.env.get('DASHBOARD_URL') || 'https://cabinet.nextlyn.ai'
    const invitationLink = `${dashboardUrl}/accept-designer-invitation?token=${invitationToken}`

    // Generate and send email
    const emailHtml = generateDesignerInvitationEmailHtml({
      designerName: body.full_name.trim(),
      invitationLink,
      expiresAt: expiresAt.toISOString(),
    })

    const emailResult = await sendEmail({
      to: emailLower,
      subject: `You're invited to join CabinetScan as a Designer`,
      html: emailHtml,
    })

    const response: InviteDesignerResponse = {
      success: true,
      invitation_id: invitation.id,
      invitation_link: invitationLink,
    }

    if (!emailResult.success) {
      console.error('Failed to send designer invitation email:', emailResult.error)
      response.error = 'Invitation created but email could not be sent. Share the invitation link manually.'
    }

    return new Response(
      JSON.stringify(response),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error in invite-designer:', error)
    return new Response(
      JSON.stringify({ success: false, error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
