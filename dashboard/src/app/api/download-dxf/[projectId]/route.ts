import { createClient } from '@/lib/supabase/server'
import { NextRequest, NextResponse } from 'next/server'
import { hasFeature, SubscriptionPlan } from '@/lib/subscription'

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ projectId: string }> }
) {
  try {
    const { projectId } = await params

    if (!projectId) {
      return NextResponse.json(
        { error: 'Project ID is required' },
        { status: 400 }
      )
    }

    const supabase = await createClient()

    // Verify user is authenticated
    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      return NextResponse.json(
        { error: 'Unauthorized' },
        { status: 401 }
      )
    }

    // Get user's showroom
    const { data: showroomUser, error: showroomUserError } = await supabase
      .from('showroom_users')
      .select('showroom_id')
      .eq('user_id', user.id)
      .single()

    if (showroomUserError || !showroomUser) {
      return NextResponse.json(
        { error: 'Showroom not found' },
        { status: 404 }
      )
    }

    // Verify project belongs to user's showroom
    const { data: project, error: projectError } = await supabase
      .from('projects')
      .select('id, showroom_id, reference_number')
      .eq('id', projectId)
      .eq('showroom_id', showroomUser.showroom_id)
      .single()

    if (projectError || !project) {
      return NextResponse.json(
        { error: 'Project not found or access denied' },
        { status: 404 }
      )
    }

    // Check subscription for autocadExport feature
    const { data: showroom, error: showroomError } = await supabase
      .from('showrooms')
      .select('subscription_plan, subscription_status')
      .eq('id', showroomUser.showroom_id)
      .single()

    if (showroomError || !showroom) {
      return NextResponse.json(
        { error: 'Showroom not found' },
        { status: 404 }
      )
    }

    // Check if autocadExport is available (trial, pro, enterprise - not basic)
    const isTrial = showroom.subscription_status === 'trial'
    const canExportDxf = isTrial || hasFeature(showroom.subscription_plan as SubscriptionPlan | null, 'autocadExport')

    if (!canExportDxf) {
      return NextResponse.json(
        { error: 'DXF export is not available on your current plan. Please upgrade to Pro or Enterprise.' },
        { status: 403 }
      )
    }

    // Call the Edge Function to generate DXF
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
    const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY

    if (!supabaseUrl || !supabaseAnonKey) {
      return NextResponse.json(
        { error: 'Server configuration error' },
        { status: 500 }
      )
    }

    const response = await fetch(`${supabaseUrl}/functions/v1/generate-dxf`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${supabaseAnonKey}`,
      },
      body: JSON.stringify({ project_id: projectId }),
    })

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({}))
      console.error('Edge Function error:', errorData)
      return NextResponse.json(
        { error: errorData.error || 'Failed to generate DXF file' },
        { status: response.status }
      )
    }

    // Get the DXF content and pass it through
    const dxfContent = await response.text()
    const contentDisposition = response.headers.get('Content-Disposition') || `attachment; filename="${project.reference_number}-floor-plan.dxf"`

    return new NextResponse(dxfContent, {
      status: 200,
      headers: {
        'Content-Type': 'application/dxf',
        'Content-Disposition': contentDisposition,
      },
    })
  } catch (error) {
    console.error('Error in DXF download route:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
