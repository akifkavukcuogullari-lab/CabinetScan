import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'

/**
 * Get the current status of a processing job.
 * Called by iOS app to poll for job completion.
 *
 * GET /functions/v1/get-job-status?job_id=<uuid>
 * Returns: { job_id, status, progress, stage, error_message }
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
      .select('id, status, progress, stage, error_message')
      .eq('id', jobId)
      .single()

    if (error || !job) {
      return new Response(
        JSON.stringify({ error: 'Job not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({
        job_id: job.id,
        status: job.status,
        progress: job.progress,
        stage: job.stage,
        error_message: job.error_message,
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
