import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import { sendEmail, generateInvitationEmailHtml } from '../_shared/email.ts'
import { encode as base64Encode } from 'https://deno.land/std@0.177.0/encoding/base64.ts'

interface SendInvitationRequest {
  showroom_id: string
  email: string
  full_name?: string
  role?: 'owner' | 'manager' | 'staff'
  invitation_message?: string
}

interface SendInvitationResponse {
  success: boolean
  invitation_id?: string
  error?: string
}

// Generate cryptographically secure random token
function generateSecureToken(): string {
  const bytes = new Uint8Array(32)
  crypto.getRandomValues(bytes)
  return base64Encode(bytes)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '')
}

// Hash token using SHA-256
async function hashToken(token: string): Promise<string> {
  const encoder = new TextEncoder()
  const data = encoder.encode(token)
  const hashBuffer = await crypto.subtle.digest('SHA-256', data)
  const hashArray = Array.from(new Uint8Array(hashBuffer))
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('')
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
        JSON.stringify({ success: false, error: 'Only super admins can send invitations' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Parse request body
    const body: SendInvitationRequest = await req.json()

    // Validate required fields
    if (!body.showroom_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'showroom_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!body.email) {
      return new Response(
        JSON.stringify({ success: false, error: 'email is required' }),
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

    // Verify showroom exists and is active
    const { data: showroom, error: showroomError } = await supabaseAdmin
      .from('showrooms')
      .select('id, name, is_active')
      .eq('id', body.showroom_id)
      .single()

    if (showroomError || !showroom) {
      return new Response(
        JSON.stringify({ success: false, error: 'Showroom not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!showroom.is_active) {
      return new Response(
        JSON.stringify({ success: false, error: 'Cannot send invitation for inactive showroom' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check for existing pending invitation
    const { data: existingInvitation } = await supabaseAdmin
      .from('showroom_invitations')
      .select('id, status, expires_at')
      .eq('showroom_id', body.showroom_id)
      .eq('email', body.email.toLowerCase())
      .eq('status', 'pending')
      .single()

    if (existingInvitation) {
      // Check if it's expired
      if (new Date(existingInvitation.expires_at) < new Date()) {
        // Update to expired status
        await supabaseAdmin
          .from('showroom_invitations')
          .update({ status: 'expired' })
          .eq('id', existingInvitation.id)
      } else {
        return new Response(
          JSON.stringify({
            success: false,
            error: 'A pending invitation already exists for this email',
            invitation_id: existingInvitation.id
          }),
          { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    // Check if user already has access to this showroom
    const { data: existingUser } = await supabaseAdmin
      .from('showroom_users')
      .select('id')
      .eq('showroom_id', body.showroom_id)
      .eq('email', body.email.toLowerCase())
      .eq('is_active', true)
      .single()

    if (existingUser) {
      return new Response(
        JSON.stringify({ success: false, error: 'User already has access to this showroom' }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Generate secure token
    const token_raw = generateSecureToken()
    const token_hash = await hashToken(token_raw)

    // Calculate expiration (7 days from now)
    const expiresAt = new Date()
    expiresAt.setDate(expiresAt.getDate() + 7)

    // Create invitation record
    const { data: invitation, error: insertError } = await supabaseAdmin
      .from('showroom_invitations')
      .insert({
        showroom_id: body.showroom_id,
        email: body.email.toLowerCase(),
        full_name: body.full_name || null,
        status: 'pending',
        token_hash,
        expires_at: expiresAt.toISOString(),
        invited_by: user.id,
        role: body.role || 'owner',
        invitation_message: body.invitation_message || null,
      })
      .select('id')
      .single()

    if (insertError || !invitation) {
      console.error('Failed to create invitation:', insertError)
      return new Response(
        JSON.stringify({ success: false, error: 'Failed to create invitation' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get showroom branding for email
    const { data: branding } = await supabaseAdmin
      .from('showroom_branding')
      .select('logo_url, primary_color')
      .eq('showroom_id', body.showroom_id)
      .single()

    // Build invitation link
    const dashboardUrl = Deno.env.get('DASHBOARD_URL') || 'https://dashboard.nextleanscan.com'
    const invitationLink = `${dashboardUrl}/auth/accept-invitation?token=${token_raw}`

    // Generate and send email
    const emailHtml = generateInvitationEmailHtml({
      showroomName: showroom.name,
      inviteeName: body.full_name || null,
      invitationLink,
      expiresAt: expiresAt.toISOString(),
      customMessage: body.invitation_message,
      logoUrl: branding?.logo_url,
      primaryColor: branding?.primary_color || '#2563EB',
    })

    const emailResult = await sendEmail({
      to: body.email,
      subject: `You're invited to manage ${showroom.name} on NextLean Scan`,
      html: emailHtml,
    })

    if (!emailResult.success) {
      // Log the error but don't fail the invitation creation
      console.error('Failed to send invitation email:', emailResult.error)
      // Optionally: you could delete the invitation here if email is critical
    }

    const response: SendInvitationResponse = {
      success: true,
      invitation_id: invitation.id,
    }

    if (!emailResult.success) {
      // Include warning about email failure
      response.error = 'Invitation created but email could not be sent. You can resend the invitation later.'
    }

    return new Response(
      JSON.stringify(response),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error in send-invitation:', error)
    return new Response(
      JSON.stringify({ success: false, error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
