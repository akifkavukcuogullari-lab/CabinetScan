import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function POST(request: NextRequest) {
  try {
    const supabase = await createClient()

    // Verify authentication
    const {
      data: { user },
    } = await supabase.auth.getUser()

    if (!user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    const body = await request.json()
    const { project_id, measurements, reference_number } = body

    if (!project_id || !measurements) {
      return NextResponse.json(
        { error: 'Missing required fields' },
        { status: 400 }
      )
    }

    // Cabinet AI Service endpoint
    const CABINET_AI_SERVICE_URL = process.env.CABINET_AI_SERVICE_URL || 'https://cabinetai.nextlyn.ai'

    // Call the Cabinet AI service
    const response = await fetch(`${CABINET_AI_SERVICE_URL}/api/generate`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        // Add any auth headers required by your microservice
        'Authorization': `Bearer ${process.env.CABINET_AI_SERVICE_API_KEY || ''}`,
      },
      body: JSON.stringify({
        project_id,
        reference_number,
        measurements,
        // Include any additional data needed by the visualization service
        room_dimensions: {
          width: measurements.room?.max_x - measurements.room?.min_x,
          depth: measurements.room?.max_z - measurements.room?.min_z,
          height: measurements.room?.ceiling_height_ft,
        },
        walls: measurements.walls,
        cabinets: measurements.cabinets,
        appliances: measurements.appliances,
      }),
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error('Cabinet AI service error:', errorText)
      return NextResponse.json(
        { error: 'Failed to generate visualization' },
        { status: 500 }
      )
    }

    const data = await response.json()

    // Return the visualization URL or data
    return NextResponse.json({
      success: true,
      visualization_url: data.url || data.visualization_url,
      data,
    })
  } catch (error) {
    console.error('Error calling visualization service:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
