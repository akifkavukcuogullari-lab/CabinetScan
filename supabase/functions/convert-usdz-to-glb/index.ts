import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'

interface ConversionRequest {
  measurement_id: string
  usdz_url: string
  showroom_code: string
}

// CloudConvert API for USDZ to GLB conversion
const CLOUDCONVERT_API_KEY = Deno.env.get('CLOUDCONVERT_API_KEY')
const CLOUDCONVERT_API_URL = 'https://api.cloudconvert.com/v2'

// Supabase Storage settings
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

async function downloadFromStorage(fileUrl: string): Promise<Uint8Array> {
  console.log(`[CONVERT] Downloading file from: ${fileUrl}`)

  const response = await fetch(fileUrl)
  if (!response.ok) {
    throw new Error(`Failed to download file: ${response.status} ${response.statusText}`)
  }

  const arrayBuffer = await response.arrayBuffer()
  console.log(`[CONVERT] Downloaded ${arrayBuffer.byteLength} bytes`)

  return new Uint8Array(arrayBuffer)
}

async function uploadToStorage(
  bucket: string,
  path: string,
  data: Uint8Array,
  contentType: string
): Promise<string> {
  console.log(`[CONVERT] Uploading to storage: ${bucket}/${path}`)

  const uploadUrl = `${SUPABASE_URL}/storage/v1/object/${bucket}/${path}`

  const response = await fetch(uploadUrl, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${SUPABASE_SERVICE_KEY}`,
      'Content-Type': contentType,
      'x-upsert': 'true',
    },
    body: data,
  })

  if (!response.ok) {
    const errorText = await response.text()
    throw new Error(`Failed to upload to storage: ${response.status} - ${errorText}`)
  }

  // Return public URL
  const publicUrl = `${SUPABASE_URL}/storage/v1/object/public/${bucket}/${path}`
  console.log(`[CONVERT] Uploaded to: ${publicUrl}`)

  return publicUrl
}

async function convertWithCloudConvert(
  usdzData: Uint8Array,
  filename: string
): Promise<Uint8Array> {
  if (!CLOUDCONVERT_API_KEY) {
    throw new Error('CLOUDCONVERT_API_KEY not configured')
  }

  console.log(`[CONVERT] Starting CloudConvert conversion for ${filename}`)

  // Step 1: Create a job with import, convert, and export tasks
  const jobResponse = await fetch(`${CLOUDCONVERT_API_URL}/jobs`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${CLOUDCONVERT_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      tasks: {
        'import-file': {
          operation: 'import/upload',
        },
        'convert-to-glb': {
          operation: 'convert',
          input: ['import-file'],
          input_format: 'usdz',
          output_format: 'glb',
        },
        'export-file': {
          operation: 'export/url',
          input: ['convert-to-glb'],
          inline: false,
          archive_multiple_files: false,
        },
      },
      tag: 'cabinetscan-usdz-to-glb',
    }),
  })

  if (!jobResponse.ok) {
    const error = await jobResponse.text()
    throw new Error(`CloudConvert job creation failed: ${error}`)
  }

  const job = await jobResponse.json()
  console.log(`[CONVERT] Created job: ${job.data.id}`)

  // Step 2: Upload the USDZ file
  const importTask = job.data.tasks.find((t: any) => t.name === 'import-file')
  if (!importTask?.result?.form) {
    throw new Error('Import task form not found')
  }

  const formData = new FormData()
  Object.entries(importTask.result.form.parameters).forEach(([key, value]) => {
    formData.append(key, value as string)
  })

  const blob = new Blob([usdzData], { type: 'model/vnd.usdz+zip' })
  formData.append('file', blob, filename)

  const uploadResponse = await fetch(importTask.result.form.url, {
    method: 'POST',
    body: formData,
  })

  if (!uploadResponse.ok) {
    throw new Error(`CloudConvert upload failed: ${uploadResponse.status}`)
  }

  console.log(`[CONVERT] File uploaded to CloudConvert`)

  // Step 3: Wait for job completion
  let attempts = 0
  const maxAttempts = 60 // 5 minutes max
  let completedJob: any = null

  while (attempts < maxAttempts) {
    await new Promise(resolve => setTimeout(resolve, 5000)) // Wait 5 seconds

    const statusResponse = await fetch(`${CLOUDCONVERT_API_URL}/jobs/${job.data.id}`, {
      headers: {
        'Authorization': `Bearer ${CLOUDCONVERT_API_KEY}`,
      },
    })

    if (!statusResponse.ok) {
      throw new Error(`Failed to check job status: ${statusResponse.status}`)
    }

    completedJob = await statusResponse.json()
    console.log(`[CONVERT] Job status: ${completedJob.data.status}`)

    if (completedJob.data.status === 'finished') {
      break
    } else if (completedJob.data.status === 'error') {
      const errorTask = completedJob.data.tasks.find((t: any) => t.status === 'error')
      throw new Error(`CloudConvert conversion failed: ${errorTask?.message || 'Unknown error'}`)
    }

    attempts++
  }

  if (!completedJob || completedJob.data.status !== 'finished') {
    throw new Error('CloudConvert job timed out')
  }

  // Step 4: Download the converted GLB file
  const exportTask = completedJob.data.tasks.find((t: any) => t.name === 'export-file')
  if (!exportTask?.result?.files?.[0]?.url) {
    throw new Error('Export URL not found in completed job')
  }

  const glbUrl = exportTask.result.files[0].url
  console.log(`[CONVERT] Downloading converted GLB from: ${glbUrl}`)

  const glbResponse = await fetch(glbUrl)
  if (!glbResponse.ok) {
    throw new Error(`Failed to download converted GLB: ${glbResponse.status}`)
  }

  const glbData = new Uint8Array(await glbResponse.arrayBuffer())
  console.log(`[CONVERT] Downloaded GLB: ${glbData.byteLength} bytes`)

  return glbData
}

// Alternative: Use a free/open-source conversion approach
// This would require a separate microservice with the USD tools
async function convertWithFallback(
  usdzData: Uint8Array,
  _filename: string
): Promise<Uint8Array | null> {
  // If CloudConvert is not configured, we can't convert
  // Return null to indicate conversion not available
  console.log('[CONVERT] No conversion service configured, skipping GLB conversion')
  return null
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
    const { measurement_id, usdz_url, showroom_code }: ConversionRequest = await req.json()

    if (!measurement_id || !usdz_url || !showroom_code) {
      return new Response(
        JSON.stringify({ error: 'measurement_id, usdz_url, and showroom_code are required' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    console.log(`[CONVERT] Starting conversion for measurement ${measurement_id}`)
    console.log(`[CONVERT] USDZ URL: ${usdz_url}`)

    // Download the USDZ file
    const usdzData = await downloadFromStorage(usdz_url)

    // Extract filename from URL
    const urlParts = usdz_url.split('/')
    const usdzFilename = urlParts[urlParts.length - 1]
    const glbFilename = usdzFilename.replace('.usdz', '.glb')

    // Convert USDZ to GLB
    let glbData: Uint8Array | null = null

    if (CLOUDCONVERT_API_KEY) {
      try {
        glbData = await convertWithCloudConvert(usdzData, usdzFilename)
      } catch (err) {
        console.error('[CONVERT] CloudConvert error:', err)
        // Try fallback
        glbData = await convertWithFallback(usdzData, usdzFilename)
      }
    } else {
      glbData = await convertWithFallback(usdzData, usdzFilename)
    }

    if (!glbData) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Conversion not available. Configure CLOUDCONVERT_API_KEY to enable USDZ to GLB conversion.',
          glb_url: null
        }),
        {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Upload GLB to storage
    const storagePath = `${showroom_code.toLowerCase()}/${glbFilename}`
    const glbUrl = await uploadToStorage('scans', storagePath, glbData, 'model/gltf-binary')

    // Update the measurement record with GLB URL
    const { error: updateError } = await supabaseAdmin
      .from('project_measurements')
      .update({ glb_file_url: glbUrl })
      .eq('id', measurement_id)

    if (updateError) {
      console.error('[CONVERT] Failed to update measurement:', updateError)
      // Still return success since file was converted
    }

    console.log(`[CONVERT] Conversion complete! GLB URL: ${glbUrl}`)

    return new Response(
      JSON.stringify({
        success: true,
        glb_url: glbUrl,
        measurement_id,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('[CONVERT] Error:', error)
    return new Response(
      JSON.stringify({
        success: false,
        error: error instanceof Error ? error.message : 'Conversion failed'
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})
