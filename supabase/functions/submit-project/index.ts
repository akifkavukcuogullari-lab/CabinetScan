import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'

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
  }
  selections: Array<{
    category_id: string
    product_id: string
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

// Call webhook with project data
async function callWebhook(
  webhookUrl: string,
  data: {
    project: any
    referenceNumber: string
    showroom: any
    submission: ProjectSubmission
    customerId: string
  }
): Promise<void> {
  const { project, referenceNumber, showroom, submission } = data

  // Fetch complete measurements data
  const { data: measurements } = await supabaseAdmin
    .from('project_measurements')
    .select('*')
    .eq('project_id', project.id)
    .single()

  // Fetch complete selections with category names
  const { data: selections } = await supabaseAdmin
    .from('project_selections')
    .select(`
      *,
      categories(name)
    `)
    .eq('project_id', project.id)

  // Build comprehensive webhook payload
  const webhookPayload = {
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
    measurements: measurements
      ? {
          room_name: measurements.room_name,
          room_type: measurements.room_type,
          total_linear_ft: measurements.total_linear_ft,
          total_sq_ft: measurements.total_sq_ft,
          wall_count: measurements.wall_count,
          window_count: measurements.window_count,
          door_count: measurements.door_count,

          // Cabinet counts
          lower_cabinet_count: measurements.roomplan_data?.cabinet_counts?.lower || 0,
          upper_cabinet_count: measurements.roomplan_data?.cabinet_counts?.upper || 0,

          // Individual lower cabinet measurements
          lower_cabinets: (measurements.roomplan_data?.cabinets?.lower || []).map((cab: any, index: number) => ({
            id: `lower_cabinet_${index + 1}`,
            type: 'lower_cabinet',
            width_ft: cab.width_ft || cab.width,
            height_ft: cab.height_ft || cab.height,
            depth_ft: cab.depth_ft || cab.depth,
            width_inches: cab.width_inches || (cab.width_ft ? cab.width_ft * 12 : null),
            height_inches: cab.height_inches || (cab.height_ft ? cab.height_ft * 12 : null),
            depth_inches: cab.depth_inches || (cab.depth_ft ? cab.depth_ft * 12 : null),
            position: cab.position || null,
            raw_data: cab,
          })),

          // Individual upper cabinet measurements
          upper_cabinets: (measurements.roomplan_data?.cabinets?.upper || []).map((cab: any, index: number) => ({
            id: `upper_cabinet_${index + 1}`,
            type: 'upper_cabinet',
            width_ft: cab.width_ft || cab.width,
            height_ft: cab.height_ft || cab.height,
            depth_ft: cab.depth_ft || cab.depth,
            width_inches: cab.width_inches || (cab.width_ft ? cab.width_ft * 12 : null),
            height_inches: cab.height_inches || (cab.height_ft ? cab.height_ft * 12 : null),
            depth_inches: cab.depth_inches || (cab.depth_ft ? cab.depth_ft * 12 : null),
            position: cab.position || null,
            raw_data: cab,
          })),

          // Individual wall measurements
          walls: (measurements.roomplan_data?.walls || []).map((wall: any, index: number) => ({
            id: `wall_${index + 1}`,
            type: 'wall',
            width_ft: wall.width_ft || wall.width,
            height_ft: wall.height_ft || wall.height,
            length_ft: wall.length_ft || wall.length,
            width_inches: wall.width_inches || (wall.width_ft ? wall.width_ft * 12 : null),
            height_inches: wall.height_inches || (wall.height_ft ? wall.height_ft * 12 : null),
            length_inches: wall.length_inches || (wall.length_ft ? wall.length_ft * 12 : null),
            position: wall.position || null,
            raw_data: wall,
          })),

          // Individual window measurements
          windows: (measurements.roomplan_data?.windows || []).map((win: any, index: number) => ({
            id: `window_${index + 1}`,
            type: 'window',
            width_ft: win.width_ft || win.width,
            height_ft: win.height_ft || win.height,
            width_inches: win.width_inches || (win.width_ft ? win.width_ft * 12 : null),
            height_inches: win.height_inches || (win.height_ft ? win.height_ft * 12 : null),
            position: win.position || null,
            raw_data: win,
          })),

          // Individual door measurements
          doors: (measurements.roomplan_data?.doors || []).map((door: any, index: number) => ({
            id: `door_${index + 1}`,
            type: 'door',
            width_ft: door.width_ft || door.width,
            height_ft: door.height_ft || door.height,
            width_inches: door.width_inches || (door.width_ft ? door.width_ft * 12 : null),
            height_inches: door.height_inches || (door.height_ft ? door.height_ft * 12 : null),
            position: door.position || null,
            raw_data: door,
          })),

          // Individual appliance measurements (stove, oven, refrigerator, dishwasher, washer/dryer)
          appliances: (measurements.roomplan_data?.appliances || []).map((app: any, index: number) => ({
            id: `appliance_${index + 1}`,
            type: app.type || app.category || 'appliance',
            category: app.category,
            width_ft: app.width_ft || app.width,
            height_ft: app.height_ft || app.height,
            depth_ft: app.depth_ft || app.depth,
            width_inches: app.width_inches || (app.width_ft ? app.width_ft * 12 : null),
            height_inches: app.height_inches || (app.height_ft ? app.height_ft * 12 : null),
            depth_inches: app.depth_inches || (app.depth_ft ? app.depth_ft * 12 : null),
            position: app.position || null,
            raw_data: app,
          })),

          // Individual sink measurements
          sinks: (measurements.roomplan_data?.sinks || []).map((sink: any, index: number) => ({
            id: `sink_${index + 1}`,
            type: 'sink',
            width_ft: sink.width_ft || sink.width,
            height_ft: sink.height_ft || sink.height,
            depth_ft: sink.depth_ft || sink.depth,
            width_inches: sink.width_inches || (sink.width_ft ? sink.width_ft * 12 : null),
            height_inches: sink.height_inches || (sink.height_ft ? sink.height_ft * 12 : null),
            depth_inches: sink.depth_inches || (sink.depth_ft ? sink.depth_ft * 12 : null),
            position: sink.position || null,
            raw_data: sink,
          })),

          // All objects in a single array for convenience
          all_objects: [
            ...(measurements.roomplan_data?.cabinets?.lower || []).map((cab: any, index: number) => ({
              id: `lower_cabinet_${index + 1}`,
              type: 'lower_cabinet',
              dimensions: { width_ft: cab.width_ft, height_ft: cab.height_ft, depth_ft: cab.depth_ft },
              position: cab.position,
            })),
            ...(measurements.roomplan_data?.cabinets?.upper || []).map((cab: any, index: number) => ({
              id: `upper_cabinet_${index + 1}`,
              type: 'upper_cabinet',
              dimensions: { width_ft: cab.width_ft, height_ft: cab.height_ft, depth_ft: cab.depth_ft },
              position: cab.position,
            })),
            ...(measurements.roomplan_data?.walls || []).map((wall: any, index: number) => ({
              id: `wall_${index + 1}`,
              type: 'wall',
              dimensions: { width_ft: wall.width_ft, height_ft: wall.height_ft, length_ft: wall.length_ft },
              position: wall.position,
            })),
            ...(measurements.roomplan_data?.windows || []).map((win: any, index: number) => ({
              id: `window_${index + 1}`,
              type: 'window',
              dimensions: { width_ft: win.width_ft, height_ft: win.height_ft },
              position: win.position,
            })),
            ...(measurements.roomplan_data?.doors || []).map((door: any, index: number) => ({
              id: `door_${index + 1}`,
              type: 'door',
              dimensions: { width_ft: door.width_ft, height_ft: door.height_ft },
              position: door.position,
            })),
            ...(measurements.roomplan_data?.appliances || []).map((app: any, index: number) => ({
              id: `appliance_${index + 1}`,
              type: app.type || app.category || 'appliance',
              category: app.category,
              dimensions: { width_ft: app.width_ft, height_ft: app.height_ft, depth_ft: app.depth_ft },
              position: app.position,
            })),
            ...(measurements.roomplan_data?.sinks || []).map((sink: any, index: number) => ({
              id: `sink_${index + 1}`,
              type: 'sink',
              dimensions: { width_ft: sink.width_ft, height_ft: sink.height_ft, depth_ft: sink.depth_ft },
              position: sink.position,
            })),
          ],

          // File URLs
          usdz_file_url: measurements.usdz_file_url,
          glb_file_url: measurements.glb_file_url,
          preview_image_url: measurements.preview_image_url,

          // Raw data for full access
          raw_measurements: measurements.measurements,
          roomplan_data: measurements.roomplan_data,
        }
      : null,
    selections: (selections || []).map((s: any) => ({
      category: s.categories?.name || 'Unknown',
      product: s.product_name_snapshot,
      price: s.product_price_snapshot,
      pricing_unit: s.pricing_unit_snapshot,
      quantity: s.quantity,
      notes: s.customer_notes,
    })),
    showroom: {
      id: showroom.id,
      name: showroom.name,
      code: showroom.showroom_code,
    },
    device_info: submission.device_info || null,
  }

  // Send webhook with timeout
  const controller = new AbortController()
  const timeoutId = setTimeout(() => controller.abort(), 10000) // 10 second timeout

  try {
    const response = await fetch(webhookUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'NextLean-Scan-Webhook/1.0',
        'X-Webhook-Event': 'project.submitted',
        'X-Project-ID': project.id,
      },
      body: JSON.stringify(webhookPayload),
      signal: controller.signal,
    })

    clearTimeout(timeoutId)

    if (!response.ok) {
      console.error(`Webhook returned status ${response.status}`)
    } else {
      console.log(`Webhook called successfully for project ${project.id}`)
    }
  } catch (err) {
    clearTimeout(timeoutId)
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
    if (submission.measurements?.roomplan_data) {
      const { error: measurementError } = await supabaseAdmin
        .from('project_measurements')
        .insert({
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
        })

      if (measurementError) {
        console.error('Error creating measurements:', measurementError)
        // Don't fail the whole submission, just log
      }
    }

    // Create product selections
    if (submission.selections && submission.selections.length > 0) {
      // Fetch product details for snapshots
      const productIds = submission.selections.map((s) => s.product_id)
      const { data: products } = await supabaseAdmin
        .from('products')
        .select('id, name, price, category_id, categories(pricing_unit)')
        .in('id', productIds)

      const productMap = new Map(products?.map((p: any) => [p.id, p]) || [])

      const selectionsToInsert = submission.selections
        .filter((s) => productMap.has(s.product_id))
        .map((s) => {
          const product = productMap.get(s.product_id) as any
          return {
            project_id: project.id,
            category_id: s.category_id,
            product_id: s.product_id,
            quantity: s.quantity || 1,
            product_name_snapshot: product.name,
            product_price_snapshot: product.price,
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

    // Call webhook if configured (async, don't block response)
    if (showroom.webhook_url) {
      callWebhook(showroom.webhook_url, {
        project,
        referenceNumber,
        showroom,
        submission,
        customerId,
      }).catch((err) => {
        console.error('Webhook call failed:', err)
      })
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
