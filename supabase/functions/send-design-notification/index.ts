import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import { sendEmail } from '../_shared/email.ts'

interface NotificationRequest {
  event_type: string
  design_request_id: string
  sender_type: 'designer' | 'showroom'
  sender_id: string
  message_preview?: string
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    if (req.method !== 'POST') {
      return new Response(
        JSON.stringify({ error: 'Method not allowed' }),
        { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify auth — allow service_role key (from Postgres trigger) or user token
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Authenticate: accept user token OR service_role key
    const token = authHeader.replace('Bearer ', '')

    // Try user auth — if it fails, check for service_role by decoding the JWT payload
    const { data: { user } } = await supabaseAdmin.auth.getUser(token)
    if (!user) {
      // Check if the token is a service_role JWT by inspecting its payload
      try {
        const payload = JSON.parse(atob(token.split('.')[1]))
        if (payload.role !== 'service_role') {
          return new Response(
            JSON.stringify({ error: 'Unauthorized' }),
            { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }
        console.log('Authenticated via service_role JWT')
      } catch {
        return new Response(
          JSON.stringify({ error: 'Unauthorized' }),
          { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    const body: NotificationRequest = await req.json()
    const { event_type, design_request_id, sender_type, message_preview } = body

    if (!event_type || !design_request_id || !sender_type) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: event_type, design_request_id, sender_type' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get design request details with related data
    const { data: request, error: requestError } = await supabaseAdmin
      .from('design_requests')
      .select('id, showroom_id, designer_id, project_id')
      .eq('id', design_request_id)
      .single()

    if (requestError || !request) {
      console.error('Design request not found:', requestError)
      return new Response(
        JSON.stringify({ error: 'Design request not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get project reference number
    const { data: project } = await supabaseAdmin
      .from('projects')
      .select('reference_number')
      .eq('id', request.project_id)
      .single()

    const projectRef = project?.reference_number || 'Unknown'

    // Determine recipient
    let recipientType: 'designer' | 'showroom'
    let recipientId: string | null = null
    let recipientEmail: string | null = null

    if (sender_type === 'designer') {
      // Designer did something -> notify showroom owner
      recipientType = 'showroom'

      // Get the primary showroom user's auth user_id (use limit(1) — there may be multiple primary users)
      const { data: showroomUsers } = await supabaseAdmin
        .from('showroom_users')
        .select('user_id')
        .eq('showroom_id', request.showroom_id)
        .eq('is_primary', true)
        .limit(1)

      const showroomUser = showroomUsers?.[0]
      if (showroomUser) {
        recipientId = showroomUser.user_id

        // Get their email from auth
        const { data: { user: recipientUser } } = await supabaseAdmin.auth.admin.getUserById(showroomUser.user_id)
        recipientEmail = recipientUser?.email || null
      }
    } else {
      // Showroom did something -> notify designer
      recipientType = 'designer'

      if (request.designer_id) {
        // recipient_id for designer notifications is designers.id (not user_id)
        recipientId = request.designer_id

        const { data: designer } = await supabaseAdmin
          .from('designers')
          .select('email')
          .eq('id', request.designer_id)
          .single()

        recipientEmail = designer?.email || null
      }
    }

    if (!recipientId) {
      console.warn('Could not determine notification recipient for event:', event_type)
      return new Response(
        JSON.stringify({ success: true, skipped: true, reason: 'No recipient found' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Build notification message and determine if email should be sent
    let notificationMessage: string
    let shouldEmail = false

    switch (event_type) {
      case 'design_accepted':
        notificationMessage = `A designer has accepted project ${projectRef}.`
        shouldEmail = true
        break
      case 'design_delivered':
        notificationMessage = `Design files have been delivered for project ${projectRef}. Please review.`
        shouldEmail = true
        break
      case 'design_approved':
        notificationMessage = `Your design for project ${projectRef} has been approved!`
        shouldEmail = true
        break
      case 'design_revision':
        notificationMessage = `Revision requested for project ${projectRef}. Please check the feedback.`
        shouldEmail = true
        break
      case 'design_dropped':
        notificationMessage = `Designer has dropped project ${projectRef}. It's back in the design pool.`
        shouldEmail = true
        break
      case 'design_completed':
        notificationMessage = `Project ${projectRef} has been marked as completed.`
        shouldEmail = true
        break
      case 'design_canceled':
        notificationMessage = `Design request for project ${projectRef} has been canceled.`
        shouldEmail = true
        break
      case 'chat_message':
        notificationMessage = message_preview
          ? `New message on project ${projectRef}: "${message_preview.substring(0, 50)}${message_preview.length > 50 ? '...' : ''}"`
          : `New message on project ${projectRef}.`
        shouldEmail = false
        break
      case 'estimate_set':
        notificationMessage = `Designer has set an estimated completion time for project ${projectRef}.`
        shouldEmail = false
        break
      default:
        notificationMessage = `Update on project ${projectRef}.`
        shouldEmail = false
    }

    // Insert notification
    const { error: insertError } = await supabaseAdmin
      .from('design_notifications')
      .insert({
        recipient_type: recipientType,
        recipient_id: recipientId,
        event_type,
        design_request_id,
        project_reference: projectRef,
        message: notificationMessage,
        email_sent: shouldEmail,
      })

    if (insertError) {
      console.error('Failed to insert notification:', insertError)
      // Don't fail the request - notification is secondary
    }

    // Send email for critical events
    if (shouldEmail && recipientEmail) {
      const dashboardUrl = Deno.env.get('DASHBOARD_URL') || 'https://cabinet.nextlyn.ai'

      const emailResult = await sendEmail({
        to: recipientEmail,
        subject: `CabinetScan Design: ${notificationMessage}`,
        html: `
          <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
            <h2 style="color: #111827; margin-bottom: 16px;">Design Update</h2>
            <p style="color: #374151; font-size: 16px; line-height: 1.6;">${notificationMessage}</p>
            <p style="margin-top: 24px;">
              <a href="${dashboardUrl}" style="display: inline-block; padding: 12px 24px; background-color: #2563EB; color: white; text-decoration: none; border-radius: 8px; font-weight: 600;">
                View in Dashboard
              </a>
            </p>
            <p style="color: #9CA3AF; font-size: 12px; margin-top: 32px;">
              This email was sent by CabinetScan
            </p>
          </div>
        `,
      })

      if (!emailResult.success) {
        console.error('Failed to send notification email:', emailResult.error)
      }
    }

    // Push notifications are handled by the Postgres trigger on design_notifications
    // which calls the send-push-notification edge function via pg_net.

    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Notification error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
