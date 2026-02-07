import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'

/**
 * Get results of a completed processing job.
 * Called by iOS app after polling shows status = 'completed'.
 *
 * GET /functions/v1/get-job-results?job_id=<uuid>
 * Returns: { job_id, measurements_data, floor_plan_png_url, validation_passed, ... }
 */
serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const url = new URL(req.url)
    const jobId = url.searchParams.get('job_id')

    if (!jobId) {
      return new Response(
        JSON.stringify({ error: 'job_id query parameter is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { data: job, error } = await supabaseAdmin
      .from('processing_jobs')
      .select(`
        id, status, measurements_data, floor_plan_png_url,
        validation_passed, validation_issues, processing_time_ms,
        scale_confidence, pipeline_version, stage_timings
      `)
      .eq('id', jobId)
      .single()

    if (error || !job) {
      return new Response(
        JSON.stringify({ error: 'Job not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (job.status !== 'completed') {
      return new Response(
        JSON.stringify({
          error: 'Job is not completed',
          status: job.status,
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({
        job_id: job.id,
        measurements_data: job.measurements_data,
        floor_plan_png_url: job.floor_plan_png_url,
        validation_passed: job.validation_passed,
        validation_issues: job.validation_issues || [],
        processing_time_ms: job.processing_time_ms,
        scale_confidence: job.scale_confidence,
        pipeline_version: job.pipeline_version,
        stage_timings: job.stage_timings,
      }),
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
