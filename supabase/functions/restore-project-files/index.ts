import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import { initiateRestore } from '../_shared/aws.ts'

interface RestoreRequest {
  project_id: string
  restore_tier?: 'Expedited' | 'Standard' | 'Bulk'
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'Method not allowed' }), {
      status: 405,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  try {
    // Verify authentication
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Get user from token
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(
      authHeader.replace('Bearer ', '')
    )

    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Invalid token' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const body: RestoreRequest = await req.json()

    if (!body.project_id) {
      return new Response(JSON.stringify({ error: 'project_id is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Verify project exists and get showroom info
    const { data: project, error: projectError } = await supabaseAdmin
      .from('projects')
      .select('id, showroom_id, storage_tier')
      .eq('id', body.project_id)
      .single()

    if (projectError || !project) {
      return new Response(JSON.stringify({ error: 'Project not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Check user has access to this showroom
    const { data: showroomUser } = await supabaseAdmin
      .from('showroom_users')
      .select('id')
      .eq('user_id', user.id)
      .eq('showroom_id', project.showroom_id)
      .eq('is_active', true)
      .single()

    // Also check if super admin
    const { data: admin } = await supabaseAdmin
      .from('admins')
      .select('id')
      .eq('user_id', user.id)
      .eq('is_active', true)
      .single()

    if (!showroomUser && !admin) {
      return new Response(JSON.stringify({ error: 'Access denied' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Check project is archived
    if (project.storage_tier !== 'archived') {
      return new Response(
        JSON.stringify({
          error: 'Project is not archived',
          current_tier: project.storage_tier,
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get archived files for this project
    const { data: archivedFiles } = await supabaseAdmin
      .from('project_archived_files')
      .select('id, s3_key, file_type')
      .eq('project_id', body.project_id)
      .eq('restore_status', 'archived')

    if (!archivedFiles?.length) {
      return new Response(
        JSON.stringify({ error: 'No archived files found for this project' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Initiate restore for each file
    const tier = body.restore_tier || 'Expedited'
    const errors: string[] = []

    for (const file of archivedFiles) {
      const result = await initiateRestore(file.s3_key, tier, 2)
      if (!result.success) {
        errors.push(`Failed to restore ${file.file_type}: ${result.error}`)
      } else {
        // Update file status
        await supabaseAdmin
          .from('project_archived_files')
          .update({
            restore_status: 'restoring',
            s3_restore_tier: tier,
            s3_restore_request_id: result.requestId,
          })
          .eq('id', file.id)
      }
    }

    // Update project status
    await supabaseAdmin
      .from('projects')
      .update({
        storage_tier: 'restoring',
        restore_requested_at: new Date().toISOString(),
      })
      .eq('id', body.project_id)

    // Get showroom notification emails
    const { data: showroom } = await supabaseAdmin
      .from('showrooms')
      .select('notification_emails')
      .eq('id', project.showroom_id)
      .single()

    // Create restore request record
    await supabaseAdmin.from('restore_requests').insert({
      project_id: body.project_id,
      requested_by: user.id,
      showroom_id: project.showroom_id,
      status: 'processing',
      notification_emails: showroom?.notification_emails || user.email,
    })

    // Calculate estimated restore time
    const estimatedHours = tier === 'Expedited' ? 5 : tier === 'Standard' ? 12 : 48

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Restore initiated',
        files_restoring: archivedFiles.length - errors.length,
        estimated_completion_hours: estimatedHours,
        tier,
        errors: errors.length > 0 ? errors : undefined,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Restore error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error', details: String(error) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
