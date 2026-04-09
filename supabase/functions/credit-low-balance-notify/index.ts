import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import { sendEmail } from '../_shared/email.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { showroom_id, balance_cents, threshold_cents } = await req.json()

    if (!showroom_id) {
      return new Response(
        JSON.stringify({ error: 'showroom_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get showroom details
    const { data: showroom } = await supabaseAdmin
      .from('showrooms')
      .select('name, email, notification_emails')
      .eq('id', showroom_id)
      .single()

    if (!showroom) {
      return new Response(
        JSON.stringify({ error: 'Showroom not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Build recipient list
    const recipients: string[] = []
    if (showroom.email) recipients.push(showroom.email)
    if (showroom.notification_emails) {
      const extras = showroom.notification_emails
        .split(',')
        .map((e: string) => e.trim())
        .filter((e: string) => e.length > 0)
      recipients.push(...extras)
    }

    if (recipients.length === 0) {
      console.log('[LOW_BALANCE] No notification emails configured for showroom', showroom_id)
      return new Response(
        JSON.stringify({ success: true, message: 'No recipients' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const balanceFormatted = `$${((balance_cents || 0) / 100).toFixed(2)}`
    const thresholdFormatted = `$${((threshold_cents || 1000) / 100).toFixed(2)}`

    const html = `
      <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 500px; margin: 0 auto; padding: 24px;">
        <h2 style="color: #1a1a1a; margin-bottom: 16px;">Low Credit Balance Alert</h2>
        <p style="color: #4a4a4a; line-height: 1.6;">
          Your <strong>${showroom.name}</strong> credit balance has dropped to <strong style="color: #dc2626;">${balanceFormatted}</strong>,
          which is below your notification threshold of ${thresholdFormatted}.
        </p>
        <p style="color: #4a4a4a; line-height: 1.6;">
          Top up your credits to keep voice agent calls and design services running without interruption.
        </p>
        <div style="margin-top: 24px;">
          <a href="${Deno.env.get('DASHBOARD_URL') || 'https://cabinetscan.nextlyn.ai'}/showroom/billing"
             style="display: inline-block; background: #2563eb; color: white; padding: 12px 24px; border-radius: 8px; text-decoration: none; font-weight: 500;">
            Top Up Credits
          </a>
        </div>
        <p style="color: #9ca3af; font-size: 12px; margin-top: 24px;">
          You can adjust your notification threshold in your billing settings.
        </p>
      </div>
    `

    // Send to all recipients
    for (const to of recipients) {
      await sendEmail({
        to,
        subject: `Low Credit Balance: ${balanceFormatted} remaining — ${showroom.name}`,
        html,
      })
    }

    console.log(`[LOW_BALANCE] Notified ${recipients.length} recipient(s) for showroom ${showroom_id}: ${balanceFormatted}`)

    return new Response(
      JSON.stringify({ success: true, recipients_count: recipients.length }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('[LOW_BALANCE] Error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
