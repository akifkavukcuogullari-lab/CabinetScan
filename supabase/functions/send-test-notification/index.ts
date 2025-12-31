import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import { sendEmail, generateProjectNotificationEmailHtml } from '../_shared/email.ts'

const DASHBOARD_URL = Deno.env.get('DASHBOARD_URL') || 'https://cabinetscan.nextlyn.ai'

interface TestNotificationRequest {
  showroom_id: string
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      {
        status: 405,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }

  try {
    // Verify authorization
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Authorization required' }),
        {
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Get user from token
    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid token' }),
        {
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    const body: TestNotificationRequest = await req.json()

    // Validate request
    if (!body.showroom_id) {
      return new Response(
        JSON.stringify({ error: 'showroom_id is required' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Verify user has access to this showroom
    const { data: showroomUser, error: accessError } = await supabaseAdmin
      .from('showroom_users')
      .select('id')
      .eq('user_id', user.id)
      .eq('showroom_id', body.showroom_id)
      .eq('is_active', true)
      .single()

    if (accessError || !showroomUser) {
      return new Response(
        JSON.stringify({ error: 'Access denied to this showroom' }),
        {
          status: 403,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Get showroom details and notification emails
    const { data: showroom, error: showroomError } = await supabaseAdmin
      .from('showrooms')
      .select('id, name, notification_emails')
      .eq('id', body.showroom_id)
      .single()

    if (showroomError || !showroom) {
      return new Response(
        JSON.stringify({ error: 'Showroom not found' }),
        {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Check if notification emails are configured
    if (!showroom.notification_emails || !showroom.notification_emails.trim()) {
      return new Response(
        JSON.stringify({
          error: 'No notification emails configured',
          message: 'Please configure notification email addresses in your showroom settings first',
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Parse email addresses
    const emails = showroom.notification_emails
      .split(',')
      .map((e: string) => e.trim())
      .filter((e: string) => e)

    if (emails.length === 0) {
      return new Response(
        JSON.stringify({
          error: 'No valid email addresses configured',
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Get showroom branding for email styling
    const { data: branding } = await supabaseAdmin
      .from('showroom_branding')
      .select('logo_url, primary_color')
      .eq('showroom_id', body.showroom_id)
      .single()

    // Generate test notification HTML
    const testProjectUrl = `${DASHBOARD_URL}/showroom/projects`
    const html = generateProjectNotificationEmailHtml({
      showroomName: showroom.name,
      customerName: 'Test Customer',
      customerEmail: 'test@example.com',
      customerPhone: '(555) 123-4567',
      submittedDate: new Date().toISOString(),
      referenceNumber: 'TEST123',
      projectViewUrl: testProjectUrl,
      logoUrl: branding?.logo_url || null,
      primaryColor: branding?.primary_color || undefined,
      isTest: true,
    })

    // Send test email to all configured addresses
    const emailResults = await Promise.allSettled(
      emails.map((email: string) =>
        sendEmail({
          to: email,
          subject: `[TEST] New Project - ${showroom.name} [TEST123]`,
          html,
        })
      )
    )

    // Check results
    const successCount = emailResults.filter(r => r.status === 'fulfilled' && r.value.success).length
    const failureCount = emailResults.length - successCount
    const failures = emailResults
      .map((r, i) => {
        if (r.status === 'rejected' || !r.value.success) {
          return {
            email: emails[i],
            error: r.status === 'rejected' ? r.reason : r.value.error,
          }
        }
        return null
      })
      .filter(f => f !== null)

    console.log(`Test notification sent: ${successCount} success, ${failureCount} failed`)

    return new Response(
      JSON.stringify({
        success: successCount > 0,
        sent_to: emails,
        success_count: successCount,
        failure_count: failureCount,
        failures: failures.length > 0 ? failures : undefined,
        message:
          successCount === emails.length
            ? `Test notification sent successfully to ${successCount} email(s)`
            : failureCount === emails.length
            ? `Failed to send test notification to all ${failureCount} email(s)`
            : `Test notification sent to ${successCount} email(s), failed to send to ${failureCount}`,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('Error sending test notification:', error)
    return new Response(
      JSON.stringify({
        error: 'Internal server error',
        details: error instanceof Error ? error.message : String(error),
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})
