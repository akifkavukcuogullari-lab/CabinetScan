import { createClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'
import { notFound, redirect } from 'next/navigation'
import Link from 'next/link'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { ModelViewer } from '@/components/3d-viewer/ModelViewer'
import { InteractiveFloorPlan } from '@/components/floor-plan/InteractiveFloorPlan'
import { DxfPreview } from '@/components/dxf-preview/DxfPreview'
import { ProjectSidebar } from '@/components/project/ProjectSidebar'
import { RoomMeasurementsSection } from '@/components/project/RoomMeasurementsSection'
import { ProductSelectionsSection } from '@/components/project/ProductSelectionsSection'
import { hasFeature, SubscriptionPlan } from '@/lib/subscription'
import {
  ArrowLeft,
  Layers,
  Rotate3d,
  FileCode,
  Lock,
  Sparkles
} from 'lucide-react'
import { WebhookPayloadViewer } from '@/components/webhook/WebhookPayloadViewer'
import { QuoteEmailSection } from '@/components/quote/QuoteEmailSection'

interface ProjectDetailPageProps {
  params: Promise<{ id: string }>
}

export default async function ProjectDetailPage({ params }: ProjectDetailPageProps) {
  const { id } = await params
  const supabase = await createClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  // Get user's showroom
  const { data: showroomUser } = await supabase
    .from('showroom_users')
    .select('showroom_id')
    .eq('user_id', user.id)
    .single()

  if (!showroomUser) redirect('/login')

  // Get showroom subscription plan
  const { data: showroom } = await supabase
    .from('showrooms')
    .select('subscription_plan, subscription_status')
    .eq('id', showroomUser.showroom_id)
    .single()

  // Check if 3D viewer is available based on plan
  // Trial users get Pro features, so check if trial is active
  const isTrial = showroom?.subscription_status === 'trial'
  const can3DView = isTrial || hasFeature(showroom?.subscription_plan as SubscriptionPlan | null, 'viewer3D')
  const canExportDxf = isTrial || hasFeature(showroom?.subscription_plan as SubscriptionPlan | null, 'autocadExport')

  // Get project with measurements and selections
  const { data: project, error } = await supabase
    .from('projects')
    .select('*')
    .eq('id', id)
    .eq('showroom_id', showroomUser.showroom_id)
    .single()

  if (error || !project) {
    notFound()
  }

  // Get measurements
  const { data: measurements } = await supabase
    .from('project_measurements')
    .select('*')
    .eq('project_id', id)

  // Get selections with product and category info
  const { data: selections } = await supabase
    .from('project_selections')
    .select(`
      *,
      categories (name),
      products (name, image_url)
    `)
    .eq('project_id', id)

  // Get quote email (latest one for this project)
  const { data: quoteEmails } = await supabase
    .from('quote_emails')
    .select('*')
    .eq('project_id', id)
    .order('created_at', { ascending: false })
    .limit(1)

  const quoteEmail = quoteEmails && quoteEmails.length > 0 ? quoteEmails[0] : null

  const statusColors: Record<string, string> = {
    draft: 'bg-gray-100 text-gray-800',
    submitted: 'bg-blue-100 text-blue-800',
    in_review: 'bg-yellow-100 text-yellow-800',
    quoted: 'bg-purple-100 text-purple-800',
    accepted: 'bg-green-100 text-green-800',
    rejected: 'bg-red-100 text-red-800',
    completed: 'bg-green-100 text-green-800',
  }

  const updateStatus = async (formData: FormData) => {
    'use server'

    const newStatus = formData.get('status') as string
    const supabase = await createClient()

    await supabase
      .from('projects')
      .update({
        status: newStatus,
        reviewed_at: newStatus === 'in_review' ? new Date().toISOString() : undefined,
      })
      .eq('id', id)

    revalidatePath(`/showroom/projects/${id}`)
  }

  // Extract scan data
  const measurement = measurements && measurements.length > 0 ? measurements[0] : null
  const hasGlbFile = measurement?.glb_file_url
  const hasUsdzFile = measurement?.usdz_file_url
  const hasFloorPlanData = measurement?.measurements?.walls?.length > 0 || measurement?.measurements?.room
  const has3DModel = hasGlbFile || hasUsdzFile
  const hasScanData = has3DModel || hasFloorPlanData

  // Calculate dominant angle from walls to auto-straighten all views
  const calculateDominantAngle = () => {
    const walls = measurement?.measurements?.walls
    if (!walls || walls.length === 0) return 0

    // Find the longest wall
    let longestWall = null
    let maxLength = 0
    for (const wall of walls) {
      if (wall.linear_ft > maxLength) {
        maxLength = wall.linear_ft
        longestWall = wall
      }
    }

    if (!longestWall?.start || !longestWall?.end) return 0

    // Calculate angle and snap to nearest 90 degrees
    const dx = longestWall.end.x - longestWall.start.x
    const dz = longestWall.end.z - longestWall.start.z
    const angle = Math.atan2(dz, dx) * (180 / Math.PI)
    const snapped = Math.round(angle / 90) * 90
    return snapped - angle
  }
  const dominantAngle = calculateDominantAngle()

  return (
    <div className="space-y-6">
      {/* Header - Compact */}
      <div className="flex items-center gap-4">
        <Link href="/showroom/projects">
          <Button variant="ghost" size="icon">
            <ArrowLeft className="h-5 w-5" />
          </Button>
        </Link>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-3">
            <h1 className="text-xl font-bold truncate">
              {project.customer_first_name} {project.customer_last_name}
            </h1>
            <Badge className={statusColors[project.status]}>
              {project.status.replace('_', ' ')}
            </Badge>
          </div>
          <p className="text-sm text-gray-500">
            Ref: <span className="font-mono">{project.reference_number}</span>
          </p>
        </div>
      </div>

      {/* Two-Column Layout */}
      <div className="grid grid-cols-1 lg:grid-cols-[1fr_320px] gap-6">
        {/* Left Column - Main Content */}
        <div className="space-y-4">
          {/* Unified Viewer with Tabs */}
          {hasScanData ? (
            <Card className="overflow-hidden">
              {/* Three-tab viewer: 2D, 3D, DXF */}
              {has3DModel && hasFloorPlanData && can3DView ? (
                <Tabs defaultValue="2d" className="w-full">
                  <div className="flex items-center justify-between px-4 py-3 border-b bg-gray-50/50">
                    <TabsList>
                      <TabsTrigger value="2d" className="gap-2">
                        <Layers className="h-4 w-4" />
                        2D Floor Plan
                      </TabsTrigger>
                      <TabsTrigger value="3d" className="gap-2">
                        <Rotate3d className="h-4 w-4" />
                        3D Model
                      </TabsTrigger>
                      {canExportDxf && (
                        <TabsTrigger value="dxf" className="gap-2">
                          <FileCode className="h-4 w-4" />
                          DXF Preview
                        </TabsTrigger>
                      )}
                    </TabsList>
                  </div>

                  <TabsContent value="2d" className="m-0">
                    <InteractiveFloorPlan measurements={measurement?.measurements} minimal />
                  </TabsContent>

                  <TabsContent value="3d" className="m-0">
                    <ModelViewer
                      glbUrl={measurement?.glb_file_url}
                      usdzUrl={measurement?.usdz_file_url}
                      previewImageUrl={measurement?.preview_image_url}
                      rotationAngle={dominantAngle}
                      minimal
                    />
                  </TabsContent>

                  {canExportDxf && (
                    <TabsContent value="dxf" className="m-0">
                      <DxfPreview measurements={measurement?.measurements} />
                    </TabsContent>
                  )}
                </Tabs>
              ) : has3DModel && hasFloorPlanData && !can3DView ? (
                // Both available but user can't view 3D - show 2D with tabs including DXF
                <Tabs defaultValue="2d" className="w-full">
                  <div className="flex items-center justify-between px-4 py-3 border-b bg-gray-50/50">
                    <TabsList>
                      <TabsTrigger value="2d" className="gap-2">
                        <Layers className="h-4 w-4" />
                        2D Floor Plan
                      </TabsTrigger>
                      <TabsTrigger value="3d" className="gap-2" disabled>
                        <Lock className="h-3 w-3 mr-1" />
                        3D Model
                        <Badge variant="secondary" className="ml-1 text-xs py-0 px-1">Pro</Badge>
                      </TabsTrigger>
                      {canExportDxf && (
                        <TabsTrigger value="dxf" className="gap-2">
                          <FileCode className="h-4 w-4" />
                          DXF Preview
                        </TabsTrigger>
                      )}
                    </TabsList>
                  </div>

                  <TabsContent value="2d" className="m-0">
                    <InteractiveFloorPlan measurements={measurement?.measurements} minimal />
                  </TabsContent>

                  <TabsContent value="3d" className="m-0">
                    <CardContent className="py-12">
                      <div className="flex flex-col items-center text-center">
                        <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-blue-100 mb-4">
                          <Rotate3d className="h-8 w-8 text-blue-600" />
                        </div>
                        <div className="flex items-center gap-2 mb-2">
                          <h3 className="text-lg font-medium">3D Model Available</h3>
                          <Badge variant="secondary" className="gap-1">
                            <Lock className="h-3 w-3" />
                            Pro
                          </Badge>
                        </div>
                        <p className="text-gray-600 max-w-md mb-4">
                          Upgrade to Pro to view the interactive 3D model captured with LiDAR technology.
                        </p>
                        <Link href="/showroom/billing">
                          <Button className="gap-2">
                            <Sparkles className="h-4 w-4" />
                            Upgrade to Pro
                          </Button>
                        </Link>
                      </div>
                    </CardContent>
                  </TabsContent>

                  {canExportDxf && (
                    <TabsContent value="dxf" className="m-0">
                      <DxfPreview measurements={measurement?.measurements} />
                    </TabsContent>
                  )}
                </Tabs>
              ) : has3DModel && can3DView ? (
                // Only 3D model file available and user can view
                <Tabs defaultValue="3d" className="w-full">
                  <div className="flex items-center justify-between px-4 py-3 border-b bg-gray-50/50">
                    <TabsList>
                      <TabsTrigger value="3d" className="gap-2">
                        <Rotate3d className="h-4 w-4" />
                        3D Model
                      </TabsTrigger>
                    </TabsList>
                  </div>

                  <TabsContent value="3d" className="m-0">
                    <ModelViewer
                      glbUrl={measurement?.glb_file_url}
                      usdzUrl={measurement?.usdz_file_url}
                      previewImageUrl={measurement?.preview_image_url}
                      rotationAngle={dominantAngle}
                      minimal
                    />
                  </TabsContent>
                </Tabs>
              ) : has3DModel && !can3DView ? (
                // Only 3D model available but user can't view
                <CardContent className="py-12">
                  <div className="flex flex-col items-center text-center">
                    <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-blue-100 mb-4">
                      <Rotate3d className="h-8 w-8 text-blue-600" />
                    </div>
                    <div className="flex items-center gap-2 mb-2">
                      <h3 className="text-lg font-medium">3D Model Available</h3>
                      <Badge variant="secondary" className="gap-1">
                        <Lock className="h-3 w-3" />
                        Pro
                      </Badge>
                    </div>
                    <p className="text-gray-600 max-w-md mb-4">
                      Upgrade to Pro to view the interactive 3D model captured with LiDAR technology.
                    </p>
                    <Link href="/showroom/billing">
                      <Button className="gap-2">
                        <Sparkles className="h-4 w-4" />
                        Upgrade to Pro
                      </Button>
                    </Link>
                  </div>
                </CardContent>
              ) : hasFloorPlanData ? (
                // Only 2D floor plan data available
                <Tabs defaultValue="2d" className="w-full">
                  <div className="flex items-center justify-between px-4 py-3 border-b bg-gray-50/50">
                    <TabsList>
                      <TabsTrigger value="2d" className="gap-2">
                        <Layers className="h-4 w-4" />
                        2D Floor Plan
                      </TabsTrigger>
                      {canExportDxf && (
                        <TabsTrigger value="dxf" className="gap-2">
                          <FileCode className="h-4 w-4" />
                          DXF Preview
                        </TabsTrigger>
                      )}
                    </TabsList>
                  </div>

                  <TabsContent value="2d" className="m-0">
                    <InteractiveFloorPlan measurements={measurement?.measurements} minimal />
                  </TabsContent>

                  {canExportDxf && (
                    <TabsContent value="dxf" className="m-0">
                      <DxfPreview measurements={measurement?.measurements} />
                    </TabsContent>
                  )}
                </Tabs>
              ) : null}
            </Card>
          ) : (
            // No scan data available
            <Card>
              <CardContent className="py-12">
                <div className="flex flex-col items-center justify-center text-center">
                  <div className="w-16 h-16 rounded-full bg-gray-100 flex items-center justify-center mb-4">
                    <Rotate3d className="h-8 w-8 text-gray-400" />
                  </div>
                  <h3 className="text-lg font-medium text-gray-900 mb-2">No Scan Data Available</h3>
                  <p className="text-gray-500 max-w-md">
                    This project does not include a room scan. The customer may have submitted selections without scanning.
                  </p>
                </div>
              </CardContent>
            </Card>
          )}

          {/* Expandable Sections */}
          <div className="space-y-3">
            {/* Room Measurements */}
            <RoomMeasurementsSection measurement={measurement} defaultOpen={true} />

            {/* Product Selections */}
            <ProductSelectionsSection selections={selections} defaultOpen={false} />

            {/* Quote Email Preview */}
            {quoteEmail && (
              <QuoteEmailSection quoteEmail={quoteEmail} />
            )}

            {/* Webhook Payload */}
            {project.webhook_payload && (
              <WebhookPayloadViewer payload={project.webhook_payload as Record<string, unknown>} />
            )}

            {/* Customer Notes */}
            {project.project_notes && (
              <Card>
                <CardContent className="py-4">
                  <h3 className="text-sm font-medium text-gray-500 mb-2">Customer Notes</h3>
                  <p className="text-gray-600">{project.project_notes}</p>
                </CardContent>
              </Card>
            )}
          </div>
        </div>

        {/* Right Column - Sidebar */}
        <div className="lg:sticky lg:top-6 lg:self-start">
          <ProjectSidebar
            project={project}
            measurement={measurement}
            canExportDxf={canExportDxf}
            onStatusChange={async (status) => {
              'use server'
              const formData = new FormData()
              formData.set('status', status)
              await updateStatus(formData)
            }}
          />
        </div>
      </div>
    </div>
  )
}
