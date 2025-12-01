import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'

interface ValidateTokenRequest {
  token: string
}

interface AcceptInvitationRequest {
  token: string
  password: string
  full_name?: string
}

interface InvitationDetails {
  invitation_id: string
  showroom_id: string
  showroom_name: string
  email: string
  full_name: string | null
  is_valid: boolean
  validation_error: string | null
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
    const url = new URL(req.url)
    const pathParts = url.pathname.split('/').filter(Boolean)
    const action = pathParts[pathParts.length - 1] // 'validate' or 'accept'

    // GET /accept-invitation?token=xxx - Validate token (for UI to show form)
    if (req.method === 'GET') {
      const token = url.searchParams.get('token')

      if (!token) {
        return new Response(
          JSON.stringify({ is_valid: false, validation_error: 'Token is required' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      const tokenHash = await hashToken(token)

      // Use the database function to validate
      const { data, error } = await supabaseAdmin.rpc('validate_invitation_token', {
        p_token_hash: tokenHash,
      })

      if (error) {
        console.error('Token validation error:', error)
        return new Response(
          JSON.stringify({ is_valid: false, validation_error: 'Failed to validate token' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      const result = data?.[0]

      if (!result) {
        return new Response(
          JSON.stringify({ is_valid: false, validation_error: 'Invitation not found' }),
          { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      const response: InvitationDetails = {
        invitation_id: result.invitation_id,
        showroom_id: result.showroom_id,
        showroom_name: result.showroom_name,
        email: result.email,
        full_name: result.full_name,
        is_valid: result.is_valid,
        validation_error: result.validation_error,
      }

      return new Response(
        JSON.stringify(response),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // POST /accept-invitation - Accept invitation and create account
    if (req.method === 'POST') {
      const body: AcceptInvitationRequest = await req.json()

      // Validate request
      if (!body.token) {
        return new Response(
          JSON.stringify({ success: false, error: 'Token is required' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      if (!body.password) {
        return new Response(
          JSON.stringify({ success: false, error: 'Password is required' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      if (body.password.length < 8) {
        return new Response(
          JSON.stringify({ success: false, error: 'Password must be at least 8 characters' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      const tokenHash = await hashToken(body.token)

      // Validate the invitation first
      const { data: validationData, error: validationError } = await supabaseAdmin.rpc(
        'validate_invitation_token',
        { p_token_hash: tokenHash }
      )

      if (validationError) {
        console.error('Token validation error:', validationError)
        return new Response(
          JSON.stringify({ success: false, error: 'Failed to validate invitation' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      const invitation = validationData?.[0]

      if (!invitation || !invitation.is_valid) {
        return new Response(
          JSON.stringify({
            success: false,
            error: invitation?.validation_error || 'Invalid invitation',
          }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      // Check if user already exists
      const { data: existingUsers } = await supabaseAdmin.auth.admin.listUsers()
      const existingUser = existingUsers?.users?.find(
        (u) => u.email?.toLowerCase() === invitation.email.toLowerCase()
      )

      let userId: string

      if (existingUser) {
        // User exists - update their password
        const { error: updateError } = await supabaseAdmin.auth.admin.updateUserById(
          existingUser.id,
          {
            password: body.password,
            email_confirm: true, // Ensure email is confirmed
          }
        )

        if (updateError) {
          console.error('Failed to update user:', updateError)
          return new Response(
            JSON.stringify({ success: false, error: 'Failed to update account' }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }

        userId = existingUser.id
      } else {
        // Create new user
        const { data: newUser, error: createError } = await supabaseAdmin.auth.admin.createUser({
          email: invitation.email,
          password: body.password,
          email_confirm: true, // Auto-confirm since they clicked invitation link
          user_metadata: {
            full_name: body.full_name || invitation.full_name || '',
            invited_to_showroom: invitation.showroom_id,
          },
        })

        if (createError || !newUser.user) {
          console.error('Failed to create user:', createError)
          return new Response(
            JSON.stringify({ success: false, error: 'Failed to create account' }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }

        userId = newUser.user.id
      }

      // Accept the invitation using database function
      const { data: acceptData, error: acceptError } = await supabaseAdmin.rpc(
        'accept_invitation',
        {
          p_invitation_id: invitation.invitation_id,
          p_user_id: userId,
        }
      )

      if (acceptError) {
        console.error('Failed to accept invitation:', acceptError)
        return new Response(
          JSON.stringify({ success: false, error: `Failed to accept invitation: ${acceptError.message}` }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      const acceptResult = acceptData?.[0]

      if (!acceptResult?.success) {
        return new Response(
          JSON.stringify({
            success: false,
            error: acceptResult?.error_message || 'Failed to accept invitation',
          }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      // Update user name if provided
      if (body.full_name && body.full_name !== invitation.full_name) {
        await supabaseAdmin
          .from('showroom_users')
          .update({ full_name: body.full_name })
          .eq('id', acceptResult.showroom_user_id)
      }

      return new Response(
        JSON.stringify({
          success: true,
          message: 'Account created successfully. You can now log in.',
          showroom_id: acceptResult.showroom_id,
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Method not allowed
    return new Response(
      JSON.stringify({ success: false, error: 'Method not allowed' }),
      { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error in accept-invitation:', error)
    return new Response(
      JSON.stringify({ success: false, error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
