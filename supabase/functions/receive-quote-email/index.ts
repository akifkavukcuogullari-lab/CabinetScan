import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'

// Expected payload from n8n
interface QuoteEmailPayload {
  to: string
  subject: string
  body_text: string
  body_html: string
  customer_name: string
  reference_number: string
  grand_total: string
  quote_summary: {
    cabinets?: string
    countertops?: string
    backsplash?: string
    total: string
  }
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Parse payload
    const payload: QuoteEmailPayload = await req.json()

    // Validate required fields
    if (!payload.reference_number || !payload.to || !payload.subject || !payload.body_html) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: reference_number, to, subject, body_html' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Find project by reference number
    const { data: project, error: projectError } = await supabaseAdmin
      .from('projects')
      .select('id, showroom_id')
      .eq('reference_number', payload.reference_number)
      .single()

    if (projectError || !project) {
      return new Response(
        JSON.stringify({ error: `Project not found: ${payload.reference_number}` }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Insert quote email
    const { data: quoteEmail, error: insertError } = await supabaseAdmin
      .from('quote_emails')
      .insert({
        project_id: project.id,
        recipient_email: payload.to,
        subject: payload.subject,
        body_html: payload.body_html,
        body_text: payload.body_text,
        customer_name: payload.customer_name,
        reference_number: payload.reference_number,
        grand_total: payload.grand_total,
        quote_summary: payload.quote_summary,
        status: 'pending'
      })
      .select()
      .single()

    if (insertError) {
      console.error('Insert error:', insertError)
      return new Response(
        JSON.stringify({ error: 'Failed to save quote email', details: insertError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Update project status to 'quoted'
    await supabaseAdmin
      .from('projects')
      .update({ status: 'quoted' })
      .eq('id', project.id)

    return new Response(
      JSON.stringify({
        success: true,
        quote_email_id: quoteEmail.id,
        message: 'Quote email received and saved'
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
