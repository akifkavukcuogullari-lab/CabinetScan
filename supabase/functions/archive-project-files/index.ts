import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import { uploadToArchive, ARCHIVE_BUCKET } from '../_shared/aws.ts'

interface ArchiveRequest {
  project_id?: string
  batch?: boolean
}

interface ProjectFile {
  type: 'usdz' | 'preview' | 'video' | 'video_thumbnail' | 'visualization_photo'
  url: string
  index?: number
}

// Extract storage path from Supabase URL
function extractStoragePath(url: string): { bucket: string; path: string } | null {
  const match = url.match(/\/storage\/v1\/object\/(?:public|sign)\/([^/]+)\/(.+?)(?:\?|$)/)
  if (match) {
    return { bucket: match[1], path: decodeURIComponent(match[2]) }
  }
  return null
}

// Get all file URLs for a project
async function getProjectFiles(projectId: string): Promise<ProjectFile[]> {
  const { data: measurements } = await supabaseAdmin
    .from('project_measurements')
    .select('usdz_file_url, preview_image_url, video_url, video_thumbnail_url, visualization_photo_urls')
    .eq('project_id', projectId)
    .single()

  if (!measurements) return []

  const files: ProjectFile[] = []

  if (measurements.usdz_file_url) {
    files.push({ type: 'usdz', url: measurements.usdz_file_url })
  }
  if (measurements.preview_image_url) {
    files.push({ type: 'preview', url: measurements.preview_image_url })
  }
  if (measurements.video_url) {
    files.push({ type: 'video', url: measurements.video_url })
  }
  if (measurements.video_thumbnail_url) {
    files.push({ type: 'video_thumbnail', url: measurements.video_thumbnail_url })
  }
  if (measurements.visualization_photo_urls?.length) {
    measurements.visualization_photo_urls.forEach((url: string, index: number) => {
      files.push({ type: 'visualization_photo', url, index })
    })
  }

  return files
}

// Download file from Supabase Storage
async function downloadFromSupabase(bucket: string, path: string): Promise<Uint8Array | null> {
  const { data, error } = await supabaseAdmin.storage.from(bucket).download(path)
  if (error || !data) {
    console.error(`Failed to download ${bucket}/${path}:`, error)
    return null
  }
  return new Uint8Array(await data.arrayBuffer())
}

// Get content type from file extension
function getContentType(path: string): string {
  const ext = path.split('.').pop()?.toLowerCase()
  const contentTypes: Record<string, string> = {
    usdz: 'model/vnd.usdz+zip',
    png: 'image/png',
    jpg: 'image/jpeg',
    jpeg: 'image/jpeg',
    mp4: 'video/mp4',
    mov: 'video/quicktime',
    json: 'application/json',
  }
  return contentTypes[ext || ''] || 'application/octet-stream'
}

// Archive a single project
async function archiveProject(projectId: string): Promise<{
  success: boolean
  filesArchived: number
  errors: string[]
}> {
  const errors: string[] = []
  let filesArchived = 0

  // Get project info
  const { data: project } = await supabaseAdmin
    .from('projects')
    .select('id, showroom_id, reference_number')
    .eq('id', projectId)
    .single()

  if (!project) {
    return { success: false, filesArchived: 0, errors: ['Project not found'] }
  }

  // Get all files
  const files = await getProjectFiles(projectId)
  if (files.length === 0) {
    // No files to archive, just mark as archived
    await supabaseAdmin
      .from('projects')
      .update({ storage_tier: 'archived', archived_at: new Date().toISOString() })
      .eq('id', projectId)
    return { success: true, filesArchived: 0, errors: [] }
  }

  // Process each file
  for (const file of files) {
    const storage = extractStoragePath(file.url)
    if (!storage) {
      errors.push(`Could not parse URL: ${file.url}`)
      continue
    }

    // Download from Supabase
    const fileData = await downloadFromSupabase(storage.bucket, storage.path)
    if (!fileData) {
      errors.push(`Failed to download: ${storage.path}`)
      continue
    }

    // Build S3 key
    const fileExt = storage.path.split('.').pop() || 'bin'
    let s3Key: string
    if (file.type === 'visualization_photo') {
      s3Key = `${project.showroom_id}/${projectId}/visualization/photo_${file.index}.${fileExt}`
    } else {
      const typeToFilename: Record<string, string> = {
        usdz: 'scan.usdz',
        preview: `preview.${fileExt}`,
        video: `video.${fileExt}`,
        video_thumbnail: `video_thumbnail.${fileExt}`,
      }
      s3Key = `${project.showroom_id}/${projectId}/${typeToFilename[file.type]}`
    }

    // Upload to S3 Glacier
    const result = await uploadToArchive(s3Key, fileData, getContentType(storage.path), {
      'original-path': storage.path,
      'original-bucket': storage.bucket,
      'project-id': projectId,
      'file-type': file.type,
    })

    if (!result.success) {
      errors.push(`Failed to archive ${file.type}: ${result.error}`)
      continue
    }

    // Track archived file in database
    await supabaseAdmin.from('project_archived_files').insert({
      project_id: projectId,
      original_bucket: storage.bucket,
      original_path: storage.path,
      s3_bucket: ARCHIVE_BUCKET,
      s3_key: s3Key,
      file_type: file.type,
      file_size_bytes: fileData.length,
      content_type: getContentType(storage.path),
      restore_status: 'archived',
    })

    // Delete from Supabase Storage
    const { error: deleteError } = await supabaseAdmin.storage
      .from(storage.bucket)
      .remove([storage.path])

    if (deleteError) {
      console.warn(`Warning: Could not delete ${storage.path} from Supabase:`, deleteError)
    }

    filesArchived++
  }

  // Update project status
  if (filesArchived > 0 || errors.length === 0) {
    await supabaseAdmin
      .from('projects')
      .update({ storage_tier: 'archived', archived_at: new Date().toISOString() })
      .eq('id', projectId)
  }

  // Clear file URLs in project_measurements (files are now in Glacier)
  await supabaseAdmin
    .from('project_measurements')
    .update({
      usdz_file_url: null,
      preview_image_url: null,
      video_url: null,
      video_thumbnail_url: null,
      visualization_photo_urls: null,
    })
    .eq('project_id', projectId)

  return {
    success: errors.length === 0,
    filesArchived,
    errors,
  }
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
    const body: ArchiveRequest = await req.json()

    // Batch mode: process all projects marked for archival
    if (body.batch) {
      const { data: projectsToArchive } = await supabaseAdmin
        .from('projects')
        .select('id')
        .eq('storage_tier', 'hot')
        .lt('created_at', new Date(Date.now() - 60 * 24 * 60 * 60 * 1000).toISOString())
        .limit(50)

      if (!projectsToArchive?.length) {
        return new Response(
          JSON.stringify({ success: true, message: 'No projects to archive' }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      const results = []
      for (const p of projectsToArchive) {
        const result = await archiveProject(p.id)
        results.push(result)
      }

      const totalArchived = results.reduce((sum, r) => sum + r.filesArchived, 0)
      const totalErrors = results.flatMap((r) => r.errors)

      return new Response(
        JSON.stringify({
          success: totalErrors.length === 0,
          projectsProcessed: projectsToArchive.length,
          filesArchived: totalArchived,
          errors: totalErrors,
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Single project mode
    if (!body.project_id) {
      return new Response(
        JSON.stringify({ error: 'project_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const result = await archiveProject(body.project_id)

    return new Response(JSON.stringify(result), {
      status: result.success ? 200 : 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('Archive error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error', details: String(error) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
