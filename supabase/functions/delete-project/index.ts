import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'

// Extract storage path from Supabase URL
function extractStoragePath(url: string): { bucket: string; path: string } | null {
  const match = url.match(/\/storage\/v1\/object\/(?:public|sign)\/([^/]+)\/(.+?)(?:\?|$)/)
  if (match) {
    return { bucket: match[1], path: decodeURIComponent(match[2]) }
  }
  return null
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Verify the user is authenticated
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing authorization' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { project_id } = await req.json()
    if (!project_id) {
      return new Response(JSON.stringify({ error: 'project_id is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Verify the user has access to this project (via showroom membership)
    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Check user has access to this project's showroom
    const { data: project } = await supabaseAdmin
      .from('projects')
      .select('id, showroom_id')
      .eq('id', project_id)
      .single()

    if (!project) {
      return new Response(JSON.stringify({ error: 'Project not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { data: showroomUser } = await supabaseAdmin
      .from('showroom_users')
      .select('id')
      .eq('user_id', user.id)
      .eq('showroom_id', project.showroom_id)
      .single()

    if (!showroomUser) {
      return new Response(JSON.stringify({ error: 'Not authorized for this project' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // ============================================
    // 1. Collect ALL storage file paths
    // ============================================
    const filesToDelete: { bucket: string; path: string }[] = []

    // Measurement files (scans bucket)
    const { data: measurements } = await supabaseAdmin
      .from('project_measurements')
      .select('usdz_file_url, video_url, video_thumbnail_url, preview_image_url, visualization_photo_urls')
      .eq('project_id', project_id)

    if (measurements) {
      for (const m of measurements) {
        for (const url of [m.usdz_file_url, m.video_url, m.video_thumbnail_url, m.preview_image_url]) {
          if (url) {
            const parsed = extractStoragePath(url)
            if (parsed) filesToDelete.push(parsed)
          }
        }
        if (m.visualization_photo_urls && Array.isArray(m.visualization_photo_urls)) {
          for (const url of m.visualization_photo_urls) {
            const parsed = extractStoragePath(url)
            if (parsed) filesToDelete.push(parsed)
          }
        }
      }
    }

    // Whiteboard files (scans bucket)
    const { data: whiteboards } = await supabaseAdmin
      .from('project_whiteboards')
      .select('drawing_data_url, thumbnail_url, photo_url')
      .eq('project_id', project_id)

    if (whiteboards) {
      for (const wb of whiteboards) {
        for (const url of [wb.drawing_data_url, wb.thumbnail_url, wb.photo_url]) {
          if (url) {
            const parsed = extractStoragePath(url)
            if (parsed) filesToDelete.push(parsed)
          }
        }
      }
    }

    // Voice agent recordings (recordings bucket)
    const { data: vaLogs } = await supabaseAdmin
      .from('voice_agent_logs')
      .select('id, recording_url')
      .eq('project_id', project_id)

    if (vaLogs) {
      for (const log of vaLogs) {
        // recording_url stores the storage path (e.g. "showroom_id/log_id.mp3")
        if (log.recording_url && !log.recording_url.startsWith('http')) {
          filesToDelete.push({ bucket: 'recordings', path: log.recording_url })
        } else if (log.recording_url) {
          const parsed = extractStoragePath(log.recording_url)
          if (parsed) filesToDelete.push(parsed)
        }
      }
    }

    // Chat attachments and design files (via design_requests)
    const { data: designReq } = await supabaseAdmin
      .from('design_requests')
      .select('id')
      .eq('project_id', project_id)
      .single()

    if (designReq) {
      // Chat message attachments
      const { data: chatMessages } = await supabaseAdmin
        .from('design_chat_messages')
        .select('file_url')
        .eq('design_request_id', designReq.id)
        .not('file_url', 'is', null)

      if (chatMessages) {
        for (const msg of chatMessages) {
          if (msg.file_url) {
            const parsed = extractStoragePath(msg.file_url)
            if (parsed) filesToDelete.push(parsed)
          }
        }
      }

      // Design files
      const { data: designFiles } = await supabaseAdmin
        .from('design_files')
        .select('file_url')
        .eq('design_request_id', designReq.id)

      if (designFiles) {
        for (const df of designFiles) {
          if (df.file_url) {
            const parsed = extractStoragePath(df.file_url)
            if (parsed) filesToDelete.push(parsed)
          }
        }
      }
    }

    // ============================================
    // 2. Delete storage files grouped by bucket
    // ============================================
    const byBucket: Record<string, string[]> = {}
    for (const f of filesToDelete) {
      if (!byBucket[f.bucket]) byBucket[f.bucket] = []
      byBucket[f.bucket].push(f.path)
    }

    for (const [bucket, paths] of Object.entries(byBucket)) {
      if (paths.length > 0) {
        const { error } = await supabaseAdmin.storage.from(bucket).remove(paths)
        if (error) {
          console.error(`[DELETE PROJECT] Error deleting from ${bucket}:`, error)
        } else {
          console.log(`[DELETE PROJECT] Deleted ${paths.length} files from ${bucket}`)
        }
      }
    }

    // ============================================
    // 3. Delete DB records (using service role — bypasses RLS)
    // ============================================
    // design_chat_messages and design_notifications cascade from design_requests
    // design_requests cascades from projects
    // But be explicit for safety
    if (designReq) {
      await supabaseAdmin.from('design_chat_messages').delete().eq('design_request_id', designReq.id)
      await supabaseAdmin.from('design_notifications').delete().eq('design_request_id', designReq.id)
      await supabaseAdmin.from('design_files').delete().eq('design_request_id', designReq.id)
      await supabaseAdmin.from('design_requests').delete().eq('id', designReq.id)
    }
    // Voice agent: credit transactions referencing these logs, then logs themselves
    if (vaLogs && vaLogs.length > 0) {
      const logIds = vaLogs.map((l: any) => l.id)
      await supabaseAdmin
        .from('showroom_credit_transactions')
        .delete()
        .in('reference_id', logIds)
        .eq('reference_type', 'voice_agent_log')
      await supabaseAdmin.from('voice_agent_logs').delete().eq('project_id', project_id)
      console.log(`[DELETE PROJECT] Deleted ${vaLogs.length} voice agent logs`)
    }

    // AI chat conversations and messages
    const { data: chatConvos } = await supabaseAdmin
      .from('ai_chat_conversations')
      .select('id')
      .eq('project_id', project_id)

    if (chatConvos && chatConvos.length > 0) {
      const convoIds = chatConvos.map((c: any) => c.id)
      await supabaseAdmin.from('ai_chat_messages').delete().in('conversation_id', convoIds)
      await supabaseAdmin.from('ai_chat_conversations').delete().eq('project_id', project_id)
    }

    await supabaseAdmin.from('project_whiteboards').delete().eq('project_id', project_id)
    await supabaseAdmin.from('quote_emails').delete().eq('project_id', project_id)
    await supabaseAdmin.from('project_addon_selections').delete().eq('project_id', project_id)
    await supabaseAdmin.from('project_selections').delete().eq('project_id', project_id)
    await supabaseAdmin.from('project_measurements').delete().eq('project_id', project_id)

    // Delete the project itself
    const { error: deleteError } = await supabaseAdmin.from('projects').delete().eq('id', project_id)

    if (deleteError) {
      console.error('[DELETE PROJECT] Error deleting project:', deleteError)
      return new Response(JSON.stringify({ error: 'Failed to delete project' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const totalFiles = filesToDelete.length
    console.log(`[DELETE PROJECT] Successfully deleted project ${project_id} (${totalFiles} storage files)`)

    return new Response(JSON.stringify({ success: true, files_deleted: totalFiles }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('[DELETE PROJECT] Unexpected error:', err)
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
