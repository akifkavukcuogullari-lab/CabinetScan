import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'

/**
 * Create a new processing job for the server pipeline.
 * Called by iOS app after uploading capture files to Supabase storage.
 *
 * POST /functions/v1/create-processing-job
 * Body: { video_url, poses_url, planes_url, photo_urls, showroom_id, metadata }
 * Returns: { job_id, status: 'queued' }
 */
serve(async (req: Request) => {
  // Handle CORS preflight
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

    const body = await req.json()

    // Validate required fields
    if (!body.video_url) {
      return new Response(
        JSON.stringify({ error: 'video_url is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!body.showroom_id) {
      return new Response(
        JSON.stringify({ error: 'showroom_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Insert processing job
    const { data: job, error: insertError } = await supabaseAdmin
      .from('processing_jobs')
      .insert({
        video_url: body.video_url,
        poses_url: body.poses_url || null,
        planes_url: body.planes_url || null,
        photo_urls: body.photo_urls || [],
        showroom_id: body.showroom_id,
        metadata: body.metadata || {},
        status: 'queued',
        progress: 0,
      })
      .select('id')
      .single()

    if (insertError) {
      console.error('Failed to create processing job:', insertError)
      return new Response(
        JSON.stringify({ error: 'Failed to create processing job', message: insertError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Trigger RunPod serverless worker
    const runpodEndpointId = Deno.env.get('RUNPOD_ENDPOINT_ID')
    const runpodApiKey = Deno.env.get('RUNPOD_API_KEY')

    if (runpodEndpointId && runpodApiKey) {
      try {
        const runpodResponse = await fetch(
          `https://api.runpod.ai/v2/${runpodEndpointId}/run`,
          {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${runpodApiKey}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              input: {
                job_id: job.id,
                video_url: body.video_url,
                poses_url: body.poses_url || null,
                planes_url: body.planes_url || null,
                metadata: body.metadata || {},
              },
            }),
          }
        )

        if (!runpodResponse.ok) {
          console.error('RunPod trigger failed:', runpodResponse.status, await runpodResponse.text())
          // Job stays queued — can be retried or picked up by polling worker
        }
      } catch (triggerErr) {
        console.error('RunPod trigger error:', triggerErr)
        // Non-fatal: job remains queued for retry
      }
    }

    return new Response(
      JSON.stringify({
        job_id: job.id,
        status: 'queued',
      }),
      {
        status: 201,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  } catch (err) {
    console.error('Unexpected error:', err)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
