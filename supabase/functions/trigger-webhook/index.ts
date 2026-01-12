import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'

interface TriggerWebhookRequest {
  project_id: string
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
    const { project_id }: TriggerWebhookRequest = await req.json()

    if (!project_id) {
      return new Response(
        JSON.stringify({ error: 'project_id is required' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Get project with webhook payload
    const { data: project, error: projectError } = await supabaseAdmin
      .from('projects')
      .select('id, showroom_id, webhook_payload, reference_number')
      .eq('id', project_id)
      .single()

    if (projectError || !project) {
      return new Response(
        JSON.stringify({ error: 'Project not found' }),
        {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    if (!project.webhook_payload) {
      return new Response(
        JSON.stringify({ error: 'No webhook payload stored for this project' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Get showroom webhook URL
    const { data: showroom, error: showroomError } = await supabaseAdmin
      .from('showrooms')
      .select('webhook_url, name')
      .eq('id', project.showroom_id)
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

    if (!showroom.webhook_url) {
      return new Response(
        JSON.stringify({ error: 'No webhook URL configured for this showroom' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Get the latest preview_image_url from project_measurements
    // (floor plan PNG may have been generated after initial submission)
    const { data: measurements } = await supabaseAdmin
      .from('project_measurements')
      .select('preview_image_url')
      .eq('project_id', project_id)
      .single()

    // Update the event type and include latest floor plan URL
    const storedPayload = project.webhook_payload as Record<string, any>
    const webhookPayload = {
      ...storedPayload,
      event: 'quote.requested',
      showroom_id: project.showroom_id, // For vector DB price catalog filtering
      // Update files.floor_plan with the latest preview_image_url
      files: {
        ...(storedPayload.files || {}),
        floor_plan: measurements?.preview_image_url || storedPayload.files?.floor_plan || null,
      },
      generate_quote: true, // Signal n8n to generate AI quote email
      triggered_at: new Date().toISOString(),
    }

    // Call the webhook
    console.log(`[WEBHOOK] Triggering webhook for project ${project_id}`)
    console.log(`[WEBHOOK] URL: ${showroom.webhook_url}`)

    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), 10000) // 10 second timeout

    try {
      const response = await fetch(showroom.webhook_url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'NextLean-Scan-Webhook/1.0',
          'X-Webhook-Event': 'quote.requested',
          'X-Project-ID': project_id,
        },
        body: JSON.stringify(webhookPayload),
        signal: controller.signal,
      })

      clearTimeout(timeoutId)

      if (!response.ok) {
        const responseText = await response.text()
        console.error(`[WEBHOOK] Webhook returned status ${response.status}: ${responseText}`)
        return new Response(
          JSON.stringify({
            success: false,
            error: `Webhook returned status ${response.status}`,
            details: responseText
          }),
          {
            status: 502,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        )
      }

      console.log(`[WEBHOOK] Successfully triggered webhook for project ${project_id}`)

      return new Response(
        JSON.stringify({
          success: true,
          message: 'Webhook triggered successfully',
          project_id: project_id,
          reference_number: project.reference_number,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    } catch (fetchError: any) {
      clearTimeout(timeoutId)
      console.error(`[WEBHOOK] Failed to call webhook:`, fetchError)

      return new Response(
        JSON.stringify({
          success: false,
          error: 'Failed to call webhook',
          details: fetchError.message
        }),
        {
          status: 502,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }
  } catch (error) {
    console.error('Error triggering webhook:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})
