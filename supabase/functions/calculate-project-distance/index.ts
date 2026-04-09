import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import { calculateDistance } from '../_shared/voice-agent/distance.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { project_id } = await req.json()
    if (!project_id) {
      return new Response(JSON.stringify({ error: 'project_id is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Get project with address
    const { data: project, error: projErr } = await supabaseAdmin
      .from('projects')
      .select('id, showroom_id, end_client_address, customer_phone, distance_miles')
      .eq('id', project_id)
      .single()

    if (projErr || !project) {
      return new Response(JSON.stringify({ error: 'Project not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Skip if distance already calculated
    if (project.distance_miles != null) {
      return new Response(JSON.stringify({ success: true, distance_miles: project.distance_miles, cached: true }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Get customer address
    const customerAddress = project.end_client_address
    if (!customerAddress) {
      await supabaseAdmin
        .from('projects')
        .update({ distance_error: 'No customer address provided' })
        .eq('id', project_id)

      return new Response(JSON.stringify({ success: false, message: 'No customer address provided' }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Get showroom address
    const { data: showroom } = await supabaseAdmin
      .from('showrooms')
      .select('address_line1, city, state, postal_code')
      .eq('id', project.showroom_id)
      .single()

    const showroomAddress = showroom
      ? [showroom.address_line1, showroom.city, showroom.state, showroom.postal_code].filter(Boolean).join(', ')
      : ''

    if (!showroomAddress) {
      await supabaseAdmin
        .from('projects')
        .update({ distance_error: 'Showroom address not configured' })
        .eq('id', project_id)

      return new Response(JSON.stringify({ success: false, message: 'Showroom address not configured' }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Calculate distance
    const result = await calculateDistance({
      customerAddress,
      showroomAddress,
    })

    if (!result) {
      await supabaseAdmin
        .from('projects')
        .update({ distance_error: 'Could not resolve address — please verify the customer address is correct' })
        .eq('id', project_id)

      console.log(`[DISTANCE] Failed for project ${project_id}: address could not be resolved`)

      return new Response(JSON.stringify({ success: false, message: 'Could not resolve address' }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Update project with distance (clear any previous error)
    await supabaseAdmin
      .from('projects')
      .update({
        distance_miles: result.distanceMiles,
        drive_time_minutes: result.driveTimeMinutes,
        distance_error: null,
      })
      .eq('id', project_id)

    console.log(`[DISTANCE] Project ${project_id}: ${result.distanceMiles} mi, ${result.driveTimeMinutes} min`)

    return new Response(JSON.stringify({
      success: true,
      distance_miles: result.distanceMiles,
      drive_time_minutes: result.driveTimeMinutes,
    }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (err) {
    console.error('[DISTANCE] Error:', err)
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
