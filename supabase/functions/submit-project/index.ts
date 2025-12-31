import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import { sendEmail, generateProjectNotificationEmailHtml } from '../_shared/email.ts'

const DASHBOARD_URL = Deno.env.get('DASHBOARD_URL') || 'https://cabinetscan.nextlyn.ai'

interface ProjectSubmission {
  showroom_id: string
  customer: {
    first_name: string
    last_name: string
    email: string
    phone: string  // Now required
    customer_type?: 'homeowner' | 'contractor'
    address_line1?: string
    city?: string
    state?: string
    zip_code?: string
  }
  end_client?: {
    first_name?: string
    last_name?: string
    phone?: string
    email?: string
    address?: string
  }
  project: {
    name: string
    notes?: string
  }
  measurements: {
    room_name?: string
    room_type?: string
    roomplan_data: Record<string, unknown>
    total_linear_ft?: number
    total_sq_ft?: number
    wall_count?: number
    window_count?: number
    door_count?: number
    measurements?: Record<string, unknown>
    usdz_file_url?: string
    preview_image_url?: string
    // Video capture fields
    video_url?: string
    video_thumbnail_url?: string
    video_duration_seconds?: number
    video_size_bytes?: number
    video_resolution?: string
    video_format?: string
    // Visualization photos (multiple angles - up to 5 photos)
    visualization_photo_urls?: string[]
  }
  selections: Array<{
    category_id: string
    product_id: string
    variant_id?: string  // Optional: for products with color variants
    quantity?: number
    customer_notes?: string
  }>
  device_info?: {
    model?: string
    ios_version?: string
    app_version?: string
  }
}

// Generate a unique reference number
function generateReferenceNumber(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' // Exclude confusing chars (0, O, 1, I)
  let result = ''
  for (let i = 0; i < 6; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length))
  }
  return result
}

// Normalize phone number to E.164 format
function normalizePhone(phone: string): string {
  // Remove all non-numeric characters
  const cleaned = phone.replace(/[^0-9]/g, '')

  // Handle US numbers (10 digits -> +1 prefix)
  if (cleaned.length === 10) {
    return '+1' + cleaned
  }
  // Already has country code (11 digits starting with 1)
  if (cleaned.length === 11 && cleaned.startsWith('1')) {
    return '+' + cleaned
  }
  // Return cleaned version for other cases
  return cleaned
}

// Find or create customer for the showroom
async function findOrCreateCustomer(
  showroomId: string,
  customerData: ProjectSubmission['customer']
): Promise<string> {
  const normalizedPhone = normalizePhone(customerData.phone)

  // Try to find existing customer by phone
  const { data: existing } = await supabaseAdmin
    .from('customers')
    .select('id')
    .eq('showroom_id', showroomId)
    .eq('phone_normalized', normalizedPhone)
    .single()

  if (existing) {
    // Update customer info (name, email, address may have changed)
    await supabaseAdmin
      .from('customers')
      .update({
        first_name: customerData.first_name,
        last_name: customerData.last_name,
        email: customerData.email,
        customer_type: customerData.customer_type || 'homeowner',
        address_line1: customerData.address_line1,
        city: customerData.city,
        state: customerData.state,
        zip_code: customerData.zip_code,
      })
      .eq('id', existing.id)

    return existing.id
  }

  // Create new customer
  const { data: newCustomer, error } = await supabaseAdmin
    .from('customers')
    .insert({
      showroom_id: showroomId,
      phone: customerData.phone,
      phone_normalized: normalizedPhone,
      first_name: customerData.first_name,
      last_name: customerData.last_name,
      email: customerData.email,
      customer_type: customerData.customer_type || 'homeowner',
      address_line1: customerData.address_line1,
      city: customerData.city,
      state: customerData.state,
      zip_code: customerData.zip_code,
    })
    .select('id')
    .single()

  if (error || !newCustomer) {
    console.error('Error creating customer:', error)
    throw new Error('Failed to create customer')
  }

  return newCustomer.id
}

// Build webhook payload (used for both sending and storing)
async function buildWebhookPayload(
  data: {
    project: any
    referenceNumber: string
    showroom: any
    submission: ProjectSubmission
    customerId: string
  }
): Promise<Record<string, unknown>> {
  const { project, referenceNumber, showroom, submission } = data

  // Fetch complete measurements data
  const { data: measurements } = await supabaseAdmin
    .from('project_measurements')
    .select('*')
    .eq('project_id', project.id)
    .single()

  // Fetch complete selections with category names and slugs
  const { data: selections } = await supabaseAdmin
    .from('project_selections')
    .select(`
      *,
      categories(name, slug)
    `)
    .eq('project_id', project.id)

  // Fetch ALL active categories (master list from super admin)
  const { data: allCategories } = await supabaseAdmin
    .from('categories')
    .select('id, name, slug')
    .eq('is_active', true)
    .order('display_order')

  // Helper function to format measurements
  const formatDimension = (feet: number | null | undefined): string => {
    if (!feet) return '0\' 0"'
    const ft = Math.floor(feet)
    const inches = Math.round((feet - ft) * 12)
    return `${ft}' ${inches}"`
  }

  // Build comprehensive webhook payload
  return {
    event: 'project.submitted',
    timestamp: new Date().toISOString(),
    project: {
      id: project.id,
      reference_number: referenceNumber,
      status: project.status,
      name: submission.project.name,
      notes: submission.project.notes,
      created_at: project.created_at,
      submitted_at: project.submitted_at,
    },
    customer: {
      id: data.customerId,
      first_name: submission.customer.first_name,
      last_name: submission.customer.last_name,
      email: submission.customer.email,
      phone: submission.customer.phone,
      customer_type: submission.customer.customer_type || 'homeowner',
      address: {
        line1: submission.customer.address_line1,
        city: submission.customer.city,
        state: submission.customer.state,
        zip_code: submission.customer.zip_code,
      },
    },
    end_client: submission.end_client || null,
    room: measurements
      ? {
          name: measurements.room_name,
          type: measurements.room_type,
          ceiling_height: formatDimension(measurements.measurements?.room?.ceiling_height_ft),
          total_area_sqft: Math.round(measurements.total_sq_ft || 0),
        }
      : null,
    measurements: measurements
      ? {
          walls: (Array.isArray(measurements.measurements?.walls) ? measurements.measurements.walls : []).map((wall: any, index: number) => ({
            id: `wall_${index + 1}`,
            length: formatDimension(wall.width_ft || wall.length_ft),
            height: formatDimension(wall.height_ft),
            linear_ft: Number((wall.width_ft || wall.length_ft || 0).toFixed(2)),
          })),

          lower_cabinets: (Array.isArray(measurements.measurements?.cabinets?.lower) ? measurements.measurements.cabinets.lower : []).map((cab: any, index: number) => ({
            id: `lower_cabinet_${index + 1}`,
            width: formatDimension(cab.width_ft),
            height: formatDimension(cab.height_ft),
            depth: formatDimension(cab.depth_ft),
          })),

          upper_cabinets: (Array.isArray(measurements.measurements?.cabinets?.upper) ? measurements.measurements.cabinets.upper : []).map((cab: any, index: number) => ({
            id: `upper_cabinet_${index + 1}`,
            width: formatDimension(cab.width_ft),
            height: formatDimension(cab.height_ft),
            depth: formatDimension(cab.depth_ft),
          })),

          appliances: (Array.isArray(measurements.measurements?.appliances) ? measurements.measurements.appliances : []).map((app: any, index: number) => ({
            id: `appliance_${index + 1}`,
            type: app.type || 'appliance',
            width: formatDimension(app.width_ft),
            height: formatDimension(app.height_ft),
            depth: formatDimension(app.depth_ft),
          })),

          sinks: (Array.isArray(measurements.measurements?.sinks) ? measurements.measurements.sinks : []).map((sink: any, index: number) => ({
            id: `sink_${index + 1}`,
            width: formatDimension(sink.width_ft),
            height: formatDimension(sink.height_ft),
            depth: formatDimension(sink.depth_ft),
          })),

          windows: (Array.isArray(measurements.measurements?.windows) ? measurements.measurements.windows : []).map((win: any, index: number) => ({
            id: `window_${index + 1}`,
            width: formatDimension(win.width_ft),
            height: formatDimension(win.height_ft),
          })),

          doors: (Array.isArray(measurements.measurements?.doors) ? measurements.measurements.doors : []).map((door: any, index: number) => ({
            id: `door_${index + 1}`,
            width: formatDimension(door.width_ft),
            height: formatDimension(door.height_ft),
          })),

          countertops: measurements.measurements?.countertop_summary
            ? {
                total_area_sqft: Number((measurements.measurements.countertop_summary.total_area_sqft || 0).toFixed(2)),
                total_linear_ft: Number((measurements.measurements.countertop_summary.total_linear_ft || 0).toFixed(2)),
                sections: (Array.isArray(measurements.measurements.countertops) ? measurements.measurements.countertops : []).map((ct: any, index: number) => ({
                  id: `countertop_${index + 1}`,
                  width: formatDimension(ct.width_ft),
                  depth: formatDimension(ct.depth_ft),
                  area_sqft: Number((ct.area_sqft || 0).toFixed(2)),
                  linear_ft: Number((ct.linear_ft || 0).toFixed(2)),
                })),
              }
            : null,

          summary: {
            total_linear_ft: Number((measurements.total_linear_ft || 0).toFixed(2)),
            wall_count: measurements.wall_count || 0,
            lower_cabinet_count: measurements.measurements?.summary?.lower_cabinet_count || 0,
            upper_cabinet_count: measurements.measurements?.summary?.upper_cabinet_count || 0,
            appliance_count: measurements.measurements?.summary?.appliance_count || 0,
            sink_count: measurements.measurements?.summary?.sink_count || 0,
            window_count: measurements.window_count || 0,
            door_count: measurements.door_count || 0,
          },
        }
      : null,
    files: measurements
      ? {
          scan_3d: measurements.usdz_file_url,
          floor_plan: measurements.preview_image_url,
          video: measurements.video_url || null,
          video_thumbnail: measurements.video_thumbnail_url || null,
          visualization_photos: measurements.visualization_photo_urls || [],
        }
      : null,
    video: measurements?.video_url
      ? {
          url: measurements.video_url,
          thumbnail: measurements.video_thumbnail_url,
          duration_seconds: measurements.video_duration_seconds,
          size_mb: measurements.video_size_bytes ? Number((measurements.video_size_bytes / (1024 * 1024)).toFixed(2)) : null,
          resolution: measurements.video_resolution,
          format: measurements.video_format,
        }
      : null,
    visualization_photos: measurements?.visualization_photo_urls && measurements.visualization_photo_urls.length > 0
      ? measurements.visualization_photo_urls.map((url, index) => ({
          url,
          index: index + 1,
          description: `Visualization photo ${index + 1} of ${measurements.visualization_photo_urls!.length}`,
        }))
      : [],
    selections: (() => {
      // Create selections object with ALL categories (null for unselected)
      const selectionsObj: Record<string, any> = {}

      // First, initialize all categories with null
      if (Array.isArray(allCategories)) {
        allCategories.forEach((cat: any) => {
          selectionsObj[cat.slug] = null
        })
      }

      // Then, fill in the selected ones
      if (Array.isArray(selections)) {
        selections.forEach((s: any) => {
          const categorySlug = s.categories?.slug || 'unknown'

          selectionsObj[categorySlug] = {
            category_name: s.categories?.name || 'Unknown',
            product: s.product_name_snapshot,
            variant: s.variant_name_snapshot || null,
            price: s.product_price_snapshot,
            pricing_unit: s.pricing_unit_snapshot,
            quantity: s.quantity,
            notes: s.customer_notes,
          }
        })
      }

      return selectionsObj
    })(),
    showroom: {
      id: showroom.id,
      name: showroom.name,
      code: showroom.showroom_code,
    },
    device_info: submission.device_info || null,
  }
}

// Trigger USDZ to GLB conversion (async, non-blocking)
async function triggerGlbConversion(
  measurementId: string,
  usdzUrl: string,
  showroomCode: string
): Promise<void> {
  const SUPABASE_URL = Deno.env.get('SUPABASE_URL')
  const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')

  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    console.log('[GLB CONVERSION] Missing environment variables, skipping conversion')
    return
  }

  const conversionUrl = `${SUPABASE_URL}/functions/v1/convert-usdz-to-glb`

  console.log(`[GLB CONVERSION] Triggering conversion for measurement ${measurementId}`)

  try {
    const response = await fetch(conversionUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
      },
      body: JSON.stringify({
        measurement_id: measurementId,
        usdz_url: usdzUrl,
        showroom_code: showroomCode,
      }),
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error(`[GLB CONVERSION] Conversion request failed: ${response.status} - ${errorText}`)
    } else {
      const result = await response.json()
      if (result.success) {
        console.log(`[GLB CONVERSION] Conversion successful: ${result.glb_url}`)
      } else {
        console.log(`[GLB CONVERSION] Conversion not available: ${result.error}`)
      }
    }
  } catch (err) {
    console.error('[GLB CONVERSION] Error calling conversion function:', err)
  }
}

// Call webhook with project data
async function callWebhook(
  webhookUrl: string,
  webhookPayload: Record<string, unknown>,
  projectId: string
): Promise<void> {
  // Send webhook with timeout
  console.log(`[WEBHOOK] Calling webhook URL: ${webhookUrl}`)
  console.log(`[WEBHOOK] Project ID: ${projectId}`)

  const controller = new AbortController()
  const timeoutId = setTimeout(() => controller.abort(), 10000) // 10 second timeout

  try {
    const response = await fetch(webhookUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'NextLean-Scan-Webhook/1.0',
        'X-Webhook-Event': 'project.submitted',
        'X-Project-ID': projectId,
      },
      body: JSON.stringify(webhookPayload),
      signal: controller.signal,
    })

    clearTimeout(timeoutId)

    if (!response.ok) {
      const responseText = await response.text()
      console.error(`[WEBHOOK] Webhook returned status ${response.status}`)
      console.error(`[WEBHOOK] Response body: ${responseText}`)
    } else {
      console.log(`[WEBHOOK] ✅ Webhook called successfully for project ${projectId}`)
      console.log(`[WEBHOOK] Response status: ${response.status}`)
    }
  } catch (err: any) {
    clearTimeout(timeoutId)
    console.error(`[WEBHOOK] ❌ Webhook call failed:`, err)
    console.error(`[WEBHOOK] Error name: ${err.name}`)
    console.error(`[WEBHOOK] Error message: ${err.message}`)
    throw err
  }
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
    const submission: ProjectSubmission = await req.json()

    // Validate required fields
    if (!submission.showroom_id) {
      return new Response(
        JSON.stringify({ error: 'showroom_id is required' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    if (!submission.customer?.first_name || !submission.customer?.last_name || !submission.customer?.email) {
      return new Response(
        JSON.stringify({ error: 'Customer first_name, last_name, and email are required' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    if (!submission.customer?.phone) {
      return new Response(
        JSON.stringify({ error: 'Customer phone number is required' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    if (!submission.project?.name) {
      return new Response(
        JSON.stringify({ error: 'Project name is required' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Verify showroom exists and is active
    const { data: showroom, error: showroomError } = await supabaseAdmin
      .from('showrooms')
      .select('id, name, showroom_code, webhook_url')
      .eq('id', submission.showroom_id)
      .eq('is_active', true)
      .single()

    if (showroomError || !showroom) {
      return new Response(
        JSON.stringify({ error: 'Showroom not found or inactive' }),
        {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Generate unique reference number
    let referenceNumber = generateReferenceNumber()
    let attempts = 0
    const maxAttempts = 10

    while (attempts < maxAttempts) {
      const { data: existing } = await supabaseAdmin
        .from('projects')
        .select('id')
        .eq('showroom_id', submission.showroom_id)
        .eq('reference_number', referenceNumber)
        .single()

      if (!existing) break

      referenceNumber = generateReferenceNumber()
      attempts++
    }

    if (attempts >= maxAttempts) {
      return new Response(
        JSON.stringify({ error: 'Failed to generate unique reference number' }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Find or create customer
    let customerId: string
    try {
      customerId = await findOrCreateCustomer(submission.showroom_id, submission.customer)
    } catch (err) {
      console.error('Error finding/creating customer:', err)
      return new Response(
        JSON.stringify({ error: 'Failed to process customer information' }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Create the project
    const { data: project, error: projectError } = await supabaseAdmin
      .from('projects')
      .insert({
        showroom_id: submission.showroom_id,
        customer_id: customerId,
        reference_number: referenceNumber,
        customer_first_name: submission.customer.first_name,
        customer_last_name: submission.customer.last_name,
        customer_email: submission.customer.email,
        customer_phone: submission.customer.phone,
        project_name: submission.project.name,
        project_notes: submission.project.notes,
        status: 'submitted',
        submitted_at: new Date().toISOString(),
        device_model: submission.device_info?.model,
        ios_version: submission.device_info?.ios_version,
        app_version: submission.device_info?.app_version,
        // End-client fields for contractor projects
        end_client_first_name: submission.end_client?.first_name,
        end_client_last_name: submission.end_client?.last_name,
        end_client_phone: submission.end_client?.phone,
        end_client_email: submission.end_client?.email,
        end_client_address: submission.end_client?.address,
      })
      .select()
      .single()

    if (projectError) {
      console.error('Error creating project:', projectError)
      return new Response(
        JSON.stringify({ error: 'Failed to create project' }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Create measurements if provided
    let measurementId: string | null = null
    if (submission.measurements?.roomplan_data) {
      const measurementData: Record<string, unknown> = {
        project_id: project.id,
        room_name: submission.measurements.room_name || 'Main Room',
        room_type: submission.measurements.room_type,
        roomplan_data: submission.measurements.roomplan_data,
        total_linear_ft: submission.measurements.total_linear_ft,
        total_sq_ft: submission.measurements.total_sq_ft,
        wall_count: submission.measurements.wall_count,
        window_count: submission.measurements.window_count,
        door_count: submission.measurements.door_count,
        measurements: submission.measurements.measurements || {},
        usdz_file_url: submission.measurements.usdz_file_url,
        preview_image_url: submission.measurements.preview_image_url,
      }

      // Add video fields if provided
      if (submission.measurements.video_url) {
        measurementData.video_url = submission.measurements.video_url
        measurementData.video_thumbnail_url = submission.measurements.video_thumbnail_url
        measurementData.video_duration_seconds = submission.measurements.video_duration_seconds
        measurementData.video_size_bytes = submission.measurements.video_size_bytes
        measurementData.video_resolution = submission.measurements.video_resolution
        measurementData.video_format = submission.measurements.video_format || 'mp4'
        measurementData.video_uploaded_at = new Date().toISOString()
      }

      // Add visualization photos if provided
      if (submission.measurements.visualization_photo_urls && submission.measurements.visualization_photo_urls.length > 0) {
        console.log(`📸 [submit-project] Received ${submission.measurements.visualization_photo_urls.length} visualization photos:`, submission.measurements.visualization_photo_urls)
        measurementData.visualization_photo_urls = submission.measurements.visualization_photo_urls
      } else {
        console.log('⚠️ [submit-project] No visualization photos in submission')
      }

      const { data: measurementResult, error: measurementError } = await supabaseAdmin
        .from('project_measurements')
        .insert(measurementData)
        .select('id')
        .single()

      if (measurementError) {
        console.error('Error creating measurements:', measurementError)
        // Don't fail the whole submission, just log
      } else if (measurementResult) {
        measurementId = measurementResult.id
      }

      // Trigger USDZ to GLB conversion if USDZ file exists (async, don't block)
      if (measurementId && submission.measurements.usdz_file_url) {
        triggerGlbConversion(
          measurementId,
          submission.measurements.usdz_file_url,
          showroom.showroom_code
        ).catch((err) => {
          console.error('[GLB CONVERSION] Failed to trigger conversion:', err)
        })
      }
    }

    // Create product selections
    if (submission.selections && submission.selections.length > 0) {
      // Fetch product details for snapshots
      const productIds = submission.selections.map((s) => s.product_id)
      const { data: products } = await supabaseAdmin
        .from('products')
        .select('id, name, price, has_variants, category_id, categories(pricing_unit)')
        .in('id', productIds)

      const productMap = new Map(products?.map((p: any) => [p.id, p]) || [])

      // Fetch variant details for selections that include variants
      const variantIds = submission.selections
        .filter((s) => s.variant_id)
        .map((s) => s.variant_id as string)

      let variantMap = new Map<string, any>()
      if (variantIds.length > 0) {
        const { data: variants } = await supabaseAdmin
          .from('product_variants')
          .select('id, name, price, product_id')
          .in('id', variantIds)

        variantMap = new Map(variants?.map((v: any) => [v.id, v]) || [])
      }

      const selectionsToInsert = submission.selections
        .filter((s) => productMap.has(s.product_id))
        .map((s) => {
          const product = productMap.get(s.product_id) as any
          const variant = s.variant_id ? variantMap.get(s.variant_id) : null

          // For products with variants, use variant price; otherwise use product price
          const effectivePrice = variant?.price ?? product.price
          const effectiveName = variant
            ? `${product.name} - ${variant.name}`
            : product.name

          return {
            project_id: project.id,
            category_id: s.category_id,
            product_id: s.product_id,
            variant_id: s.variant_id || null,
            quantity: s.quantity || 1,
            product_name_snapshot: effectiveName,
            variant_name_snapshot: variant?.name || null,
            product_price_snapshot: effectivePrice,
            pricing_unit_snapshot: product.categories?.pricing_unit || 'none',
            customer_notes: s.customer_notes,
          }
        })

      if (selectionsToInsert.length > 0) {
        const { error: selectionsError } = await supabaseAdmin
          .from('project_selections')
          .insert(selectionsToInsert)

        if (selectionsError) {
          console.error('Error creating selections:', selectionsError)
          // Don't fail the whole submission, just log
        }
      }
    }

    // Build and save webhook payload (always save if showroom has webhook configured)
    // This allows viewing the payload in the dashboard even if webhook delivery fails
    if (showroom.webhook_url) {
      // Build webhook payload
      const webhookPayload = await buildWebhookPayload({
        project,
        referenceNumber,
        showroom,
        submission,
        customerId,
      })

      // Save webhook payload to project (async, don't block)
      supabaseAdmin
        .from('projects')
        .update({ webhook_payload: webhookPayload })
        .eq('id', project.id)
        .then(({ error }) => {
          if (error) {
            console.error('Error saving webhook payload:', error)
          } else {
            console.log(`[WEBHOOK] Saved webhook payload for project ${project.id}`)
          }
        })

      // Call webhook (async, don't block response)
      callWebhook(showroom.webhook_url, webhookPayload, project.id).catch((err) => {
        console.error('Webhook call failed:', err)
      })
    }

    // Send email notifications (async, non-blocking)
    if (showroom.notification_emails) {
      const emails = showroom.notification_emails.split(',').map((e: string) => e.trim()).filter((e: string) => e)

      if (emails.length > 0) {
        console.log(`[EMAIL] Sending notifications to ${emails.length} recipient(s)`)

        // Get branding for email styling
        supabaseAdmin
          .from('showroom_branding')
          .select('logo_url, primary_color')
          .eq('showroom_id', submission.showroom_id)
          .single()
          .then(({ data: branding }) => {
            const projectUrl = `${DASHBOARD_URL}/showroom/projects/${project.id}`

            const html = generateProjectNotificationEmailHtml({
              showroomName: showroom.name,
              customerName: `${submission.customer.first_name} ${submission.customer.last_name}`,
              customerEmail: submission.customer.email,
              customerPhone: submission.customer.phone,
              submittedDate: project.submitted_at,
              referenceNumber,
              projectViewUrl: projectUrl,
              logoUrl: branding?.logo_url || null,
              primaryColor: branding?.primary_color || undefined,
            })

            // Send async (don't block response)
            Promise.all(
              emails.map((email: string) =>
                sendEmail({
                  to: email,
                  subject: `New Project - ${showroom.name} [${referenceNumber}]`,
                  html,
                })
              )
            )
              .then((results) => {
                const successCount = results.filter((r: any) => r.success).length
                console.log(`[EMAIL] Notifications sent: ${successCount}/${emails.length} successful`)
              })
              .catch((err: any) => {
                console.error('[EMAIL] Error sending notifications:', err)
              })
          })
          .catch((err: any) => {
            console.error('[EMAIL] Error fetching branding for notifications:', err)
          })
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        project_id: project.id,
        reference_number: referenceNumber,
        showroom_name: showroom.name,
      }),
      {
        status: 201,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('Error submitting project:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})
