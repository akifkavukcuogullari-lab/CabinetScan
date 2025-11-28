import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'

interface ProjectSubmission {
  showroom_id: string
  customer: {
    first_name: string
    last_name: string
    email: string
    phone?: string
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
      .select('id, name')
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

    // Create the project
    const { data: project, error: projectError } = await supabaseAdmin
      .from('projects')
      .insert({
        showroom_id: submission.showroom_id,
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
