import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import { downloadFromArchive } from '../_shared/aws.ts'
import { sendEmail } from '../_shared/email.ts'

const DASHBOARD_URL = Deno.env.get('DASHBOARD_URL') || 'https://qa.cabinetscan.nextlyn.ai'
const WEBHOOK_SECRET = Deno.env.get('RESTORE_WEBHOOK_SECRET') || ''

interface RestoreCompleteRequest {
  project_id: string
  s3_key?: string
  webhook_secret?: string
}

// Upload file back to Supabase Storage
async function uploadToSupabase(
  bucket: string,
  path: string,
  data: Uint8Array,
  contentType: string
): Promise<string | null> {
  const { data: uploadData, error } = await supabaseAdmin.storage
    .from(bucket)
    .upload(path, data, {
      contentType,
      upsert: true,
    })

  if (error) {
    console.error(`Failed to upload to Supabase ${bucket}/${path}:`, error)
    return null
  }

  const { data: urlData } = supabaseAdmin.storage.from(bucket).getPublicUrl(uploadData.path)
  return urlData.publicUrl
}

// Generate restore complete email HTML
function generateRestoreEmailHtml(options: {
  showroomName: string
  projectName: string
  referenceNumber: string
  expiresAt: string
  projectUrl: string
  logoUrl?: string
  primaryColor?: string
}): string {
  const {
    showroomName,
    projectName,
    referenceNumber,
    expiresAt,
    projectUrl,
    logoUrl,
    primaryColor = '#2563EB',
  } = options

  const expiresDate = new Date(expiresAt).toLocaleDateString('en-US', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })

  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Project Files Restored - ${referenceNumber}</title>
</head>
<body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #f3f4f6;">
  <table role="presentation" style="width: 100%; border-collapse: collapse;">
    <tr>
      <td align="center" style="padding: 40px 20px;">
        <table role="presentation" style="width: 100%; max-width: 600px; background-color: #ffffff; border-radius: 12px; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);">
          <!-- Header -->
          <tr>
            <td style="padding: 40px 40px 20px; text-align: center; border-bottom: 1px solid #e5e7eb;">
              ${logoUrl ? `<img src="${logoUrl}" alt="${showroomName}" style="max-height: 60px; max-width: 200px; margin-bottom: 16px;">` : ''}
              <h1 style="margin: 0; font-size: 24px; font-weight: 700; color: #111827;">
                Project Files Restored
              </h1>
            </td>
          </tr>

          <!-- Body -->
          <tr>
            <td style="padding: 40px;">
              <p style="margin: 0 0 20px; font-size: 16px; line-height: 1.6; color: #374151;">
                Great news! The archived files for project <strong style="color: ${primaryColor};">${projectName}</strong>
                (Reference: ${referenceNumber}) have been restored and are now available for download.
              </p>

              <div style="margin: 24px 0; padding: 16px; background-color: #fef3c7; border-radius: 8px; border-left: 4px solid #f59e0b;">
                <p style="margin: 0; font-size: 14px; color: #92400e;">
                  <strong>Important:</strong> These files will only be available until
                  <strong>${expiresDate}</strong>. After this time, they will be automatically
                  re-archived to cold storage.
                </p>
              </div>

              <table role="presentation" style="width: 100%; margin-top: 32px;">
                <tr>
                  <td align="center">
                    <a href="${projectUrl}"
                       style="display: inline-block; padding: 16px 32px; background-color: ${primaryColor}; color: #ffffff; text-decoration: none; font-size: 16px; font-weight: 600; border-radius: 8px;">
                      View Project Files
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="padding: 24px 40px; background-color: #f9fafb; border-radius: 0 0 12px 12px; border-top: 1px solid #e5e7eb;">
              <p style="margin: 0; font-size: 12px; color: #9ca3af; text-align: center;">
                This email was sent by CabinetHub
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
`
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
    const body: RestoreCompleteRequest = await req.json()

    // Verify webhook secret (set by AWS Lambda)
    if (WEBHOOK_SECRET && body.webhook_secret !== WEBHOOK_SECRET) {
      return new Response(JSON.stringify({ error: 'Invalid webhook secret' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!body.project_id) {
      return new Response(JSON.stringify({ error: 'project_id is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Get all restoring files for this project
    const { data: archivedFiles } = await supabaseAdmin
      .from('project_archived_files')
      .select('*')
      .eq('project_id', body.project_id)
      .eq('restore_status', 'restoring')

    if (!archivedFiles?.length) {
      return new Response(
        JSON.stringify({ error: 'No files in restoring state' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Download each file from S3 and upload to Supabase
    const newUrls: Record<string, string | string[]> = {}
    const visualizationPhotos: string[] = []
    const errors: string[] = []

    for (const file of archivedFiles) {
      const result = await downloadFromArchive(file.s3_key)
      if (!result.success || !result.data) {
        errors.push(`Failed to download ${file.file_type}: ${result.error}`)
        continue
      }

      // Upload back to Supabase
      const newUrl = await uploadToSupabase(
        file.original_bucket,
        file.original_path,
        result.data,
        file.content_type || 'application/octet-stream'
      )

      if (!newUrl) {
        errors.push(`Failed to upload ${file.file_type} to Supabase`)
        continue
      }

      // Track URL by type
      if (file.file_type === 'visualization_photo') {
        visualizationPhotos.push(newUrl)
      } else {
        const fieldMap: Record<string, string> = {
          usdz: 'usdz_file_url',
          preview: 'preview_image_url',
          video: 'video_url',
          video_thumbnail: 'video_thumbnail_url',
        }
        const field = fieldMap[file.file_type]
        if (field) {
          newUrls[field] = newUrl
        }
      }

      // Update file record
      await supabaseAdmin
        .from('project_archived_files')
        .update({
          restore_status: 'restored',
          restore_completed_at: new Date().toISOString(),
        })
        .eq('id', file.id)
    }

    // Add visualization photos if any
    if (visualizationPhotos.length > 0) {
      newUrls['visualization_photo_urls'] = visualizationPhotos
    }

    // Update project_measurements with new URLs
    if (Object.keys(newUrls).length > 0) {
      await supabaseAdmin
        .from('project_measurements')
        .update(newUrls)
        .eq('project_id', body.project_id)
    }

    // Calculate expiry (48 hours from now)
    const expiresAt = new Date(Date.now() + 48 * 60 * 60 * 1000).toISOString()

    // Update project status
    await supabaseAdmin
      .from('projects')
      .update({
        storage_tier: 'hot',
        restore_available_until: expiresAt,
        archived_at: null,
        restore_requested_at: null,
      })
      .eq('id', body.project_id)

    // Update restore request
    await supabaseAdmin
      .from('restore_requests')
      .update({
        status: 'completed',
        completed_at: new Date().toISOString(),
        expires_at: expiresAt,
      })
      .eq('project_id', body.project_id)
      .eq('status', 'processing')

    // Get restore request for notification email
    const { data: restoreRequest } = await supabaseAdmin
      .from('restore_requests')
      .select('notification_emails')
      .eq('project_id', body.project_id)
      .eq('status', 'completed')
      .order('completed_at', { ascending: false })
      .limit(1)
      .single()

    if (restoreRequest?.notification_emails) {
      // Get project and showroom info for email
      const { data: project } = await supabaseAdmin
        .from('projects')
        .select(`
          project_name,
          reference_number,
          showrooms!inner(name, showroom_branding(logo_url, primary_color))
        `)
        .eq('id', body.project_id)
        .single()

      if (project) {
        const showroom = project.showrooms as { name: string; showroom_branding?: { logo_url?: string; primary_color?: string } }
        const branding = showroom.showroom_branding

        const html = generateRestoreEmailHtml({
          showroomName: showroom.name,
          projectName: project.project_name || 'Room Scan',
          referenceNumber: project.reference_number,
          expiresAt,
          projectUrl: `${DASHBOARD_URL}/showroom/projects/${body.project_id}`,
          logoUrl: branding?.logo_url,
          primaryColor: branding?.primary_color,
        })

        // Send to each notification email
        const emails = restoreRequest.notification_emails.split(',').map((e: string) => e.trim())
        for (const email of emails) {
          if (email) {
            await sendEmail({
              to: email,
              subject: `Files Restored - ${project.project_name || 'Room Scan'} [${project.reference_number}]`,
              html,
            })
          }
        }

        // Mark notification sent
        await supabaseAdmin
          .from('restore_requests')
          .update({ notification_sent_at: new Date().toISOString() })
          .eq('project_id', body.project_id)
          .eq('status', 'completed')
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        files_restored: archivedFiles.length - errors.length,
        expires_at: expiresAt,
        errors: errors.length > 0 ? errors : undefined,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Complete restore error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error', details: String(error) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
