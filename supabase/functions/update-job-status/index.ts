import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'

/**
 * Update processing job status and results.
 * Called by the server worker (RunPod/Modal) during pipeline execution.
 * Requires service_role key for authorization.
 *
 * POST /functions/v1/update-job-status
 * Body: { job_id, status?, progress?, stage?, error_message?, measurements_data?, ... }
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

    // Verify service role authorization
    const authHeader = req.headers.get('Authorization')
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!authHeader || !serviceRoleKey || authHeader !== `Bearer ${serviceRoleKey}`) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized — service role key required' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const body = await req.json()

    if (!body.job_id) {
      return new Response(
        JSON.stringify({ error: 'job_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Build update object from provided fields
    const update: Record<string, unknown> = {}

    if (body.status !== undefined) update.status = body.status
    if (body.progress !== undefined) update.progress = body.progress
    if (body.stage !== undefined) update.stage = body.stage
    if (body.error_message !== undefined) update.error_message = body.error_message
    if (body.worker_id !== undefined) update.worker_id = body.worker_id

    // Track timing transitions
    if (body.status === 'processing' && !body.started_at) {
      update.started_at = new Date().toISOString()
    }
    if (body.status === 'completed' || body.status === 'failed') {
      update.completed_at = new Date().toISOString()
    }

    // Results fields (set on completion)
    if (body.measurements_data !== undefined) update.measurements_data = body.measurements_data
    if (body.floor_plan_png_url !== undefined) update.floor_plan_png_url = body.floor_plan_png_url
    if (body.measurements_json_url !== undefined) update.measurements_json_url = body.measurements_json_url
    if (body.scale_confidence !== undefined) update.scale_confidence = body.scale_confidence
    if (body.validation_passed !== undefined) update.validation_passed = body.validation_passed
    if (body.validation_issues !== undefined) update.validation_issues = body.validation_issues
    if (body.processing_time_ms !== undefined) update.processing_time_ms = body.processing_time_ms
    if (body.stage_timings !== undefined) update.stage_timings = body.stage_timings

    if (Object.keys(update).length === 0) {
      return new Response(
        JSON.stringify({ error: 'No fields to update' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { error: updateError } = await supabaseAdmin
      .from('processing_jobs')
      .update(update)
      .eq('id', body.job_id)

    if (updateError) {
      console.error('Failed to update job:', updateError)
      return new Response(
        JSON.stringify({ error: 'Failed to update job', message: updateError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({ success: true, job_id: body.job_id }),
      {
        status: 200,
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
