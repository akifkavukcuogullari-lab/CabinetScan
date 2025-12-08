import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'

interface SendRequest {
  quote_email_id: string
  // Optional: updated email content (if edited in dashboard)
  recipient_email?: string
  subject?: string
  body_html?: string
  body_text?: string
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { quote_email_id, recipient_email, subject, body_html, body_text }: SendRequest = await req.json()

    if (!quote_email_id) {
      return new Response(
        JSON.stringify({ error: 'quote_email_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Fetch the quote email with project info
    const { data: quoteEmail, error: fetchError } = await supabaseAdmin
      .from('quote_emails')
      .select(`
        *,
        projects!inner (
          id,
          showroom_id,
          reference_number,
          customer_first_name,
          customer_last_name,
          customer_email,
          showrooms!inner (
            id,
            name,
            quote_webhook_url
          )
        )
      `)
      .eq('id', quote_email_id)
      .single()

    if (fetchError || !quoteEmail) {
      return new Response(
        JSON.stringify({ error: 'Quote email not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check if already sent
    if (quoteEmail.status === 'sent') {
      return new Response(
        JSON.stringify({ error: 'Quote email already sent' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Use updated values if provided, otherwise use stored values
    const emailToSend = {
      to: recipient_email || quoteEmail.recipient_email,
      subject: subject || quoteEmail.subject,
      body_html: body_html || quoteEmail.body_html,
      body_text: body_text || quoteEmail.body_text,
      customer_name: quoteEmail.customer_name,
      reference_number: quoteEmail.reference_number,
      grand_total: quoteEmail.grand_total,
      quote_summary: quoteEmail.quote_summary,
      showroom_name: quoteEmail.projects.showrooms.name
    }

    // Update the quote email record with any changes
    const updateData: Record<string, unknown> = {
      status: 'sent',
      sent_at: new Date().toISOString()
    }

    // If content was edited, save the updates
    if (recipient_email) updateData.recipient_email = recipient_email
    if (subject) updateData.subject = subject
    if (body_html) updateData.body_html = body_html
    if (body_text) updateData.body_text = body_text

    // Get the webhook URL
    const webhookUrl = quoteEmail.projects.showrooms.quote_webhook_url

    // If webhook URL is configured, send to n8n
    if (webhookUrl) {
      try {
        const webhookResponse = await fetch(webhookUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            action: 'send_email',
            ...emailToSend
          })
        })

        if (!webhookResponse.ok) {
          const errorText = await webhookResponse.text()
          console.error('Webhook failed:', errorText)
          // Don't fail the whole request, just log it
        }
      } catch (webhookError) {
        console.error('Webhook error:', webhookError)
        // Continue - we'll still mark it as sent
      }
    }

    // Update the quote email status
    const { error: updateError } = await supabaseAdmin
      .from('quote_emails')
      .update(updateData)
      .eq('id', quote_email_id)

    if (updateError) {
      console.error('Update error:', updateError)
      return new Response(
        JSON.stringify({ error: 'Failed to update quote email status' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Quote email sent successfully',
        webhook_triggered: !!webhookUrl
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error', details: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
