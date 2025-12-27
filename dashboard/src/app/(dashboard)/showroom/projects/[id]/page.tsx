import { createClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'
import { notFound, redirect } from 'next/navigation'
import Link from 'next/link'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { ModelViewer } from '@/components/3d-viewer/ModelViewer'
import { InteractiveFloorPlan } from '@/components/floor-plan/InteractiveFloorPlan'
import { hasFeature, SubscriptionPlan } from '@/lib/subscription'
import {
  ArrowLeft,
  User,
  Mail,
  Phone,
  Calendar,
  Ruler,
  Box,
  DoorOpen,
  Square,
  Layers,
  Rotate3d,
  Lock,
  Sparkles,
  Download,
  Video,
  FileBox,
  FileCode,
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
  const hasVideoFile = measurement?.video_url
  const visualizationPhotos = measurement?.visualization_photo_urls || []
  const hasVisualizationPhotos = visualizationPhotos.length > 0
  const hasFloorPlanData = measurement?.measurements?.walls?.length > 0 || measurement?.measurements?.room
  const has3DModel = hasGlbFile || hasUsdzFile
  const hasScanData = has3DModel || hasFloorPlanData
  const hasDownloadableFiles = hasGlbFile || hasUsdzFile || hasVideoFile || hasVisualizationPhotos || hasFloorPlanData

  // DEBUG: Log photo data
  console.log('📸 [Dashboard] measurement:', measurement)
  console.log('📸 [Dashboard] visualization_photo_urls:', measurement?.visualization_photo_urls)
  console.log('📸 [Dashboard] visualizationPhotos:', visualizationPhotos)
  console.log('📸 [Dashboard] hasVisualizationPhotos:', hasVisualizationPhotos)
  console.log('📸 [Dashboard] hasDownloadableFiles:', hasDownloadableFiles)

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-start gap-4">
        <Link href="/showroom/projects">
          <Button variant="ghost" size="icon">
            <ArrowLeft className="h-5 w-5" />
          </Button>
        </Link>
        <div className="flex-1">
          <div className="flex items-center gap-3">
            <h1 className="text-2xl font-bold">{project.project_name}</h1>
            <Badge className={statusColors[project.status]}>
              {project.status.replace('_', ' ')}
            </Badge>
          </div>
          <p className="text-gray-500">
            Reference: <span className="font-mono">{project.reference_number}</span>
          </p>
        </div>
        <form action={updateStatus}>
          <select
            name="status"
            defaultValue={project.status}
            className="h-10 px-3 rounded-md border border-input bg-background text-sm"
          >
            <option value="submitted">Submitted</option>
            <option value="in_review">In Review</option>
            <option value="quoted">Quoted</option>
            <option value="accepted">Accepted</option>
            <option value="rejected">Rejected</option>
            <option value="completed">Completed</option>
          </select>
          <Button type="submit" className="ml-2">
            Update Status
          </Button>
        </form>
      </div>

      {/* HERO: 3D/2D Scan Visualization */}
      {hasScanData ? (
        <div className="space-y-2">
          <div className="flex items-center gap-2 text-lg font-semibold">
            <Rotate3d className="h-5 w-5 text-blue-600" />
            Room Scan
          </div>

          {has3DModel && hasFloorPlanData && can3DView ? (
            // Both 3D and 2D available AND user can view 3D - show tabs
            <Tabs defaultValue="2d" className="w-full">
              <TabsList className="mb-4">
                <TabsTrigger value="2d" className="flex items-center gap-2">
                  <Layers className="h-4 w-4" />
                  2D Floor Plan
                </TabsTrigger>
                <TabsTrigger value="3d" className="flex items-center gap-2">
                  <Rotate3d className="h-4 w-4" />
                  3D Model
                </TabsTrigger>
              </TabsList>

              <TabsContent value="2d" className="mt-0">
                <InteractiveFloorPlan measurements={measurement.measurements} />
              </TabsContent>

              <TabsContent value="3d" className="mt-0">
                <ModelViewer
                  glbUrl={measurement.glb_file_url}
                  usdzUrl={measurement.usdz_file_url}
                  previewImageUrl={measurement.preview_image_url}
                  title="3D Room Scan"
                  description="Interactive 3D model captured with LiDAR - drag to rotate, scroll to zoom"
                />
              </TabsContent>
            </Tabs>
          ) : has3DModel && hasFloorPlanData && !can3DView ? (
            // Both 3D and 2D available but user can't view 3D - show 2D only with upgrade prompt
            <div className="space-y-4">
              <InteractiveFloorPlan measurements={measurement.measurements} />
              <Card className="border-blue-200 bg-blue-50/50">
                <CardContent className="py-6">
                  <div className="flex items-center gap-4">
                    <div className="flex-shrink-0">
                      <div className="inline-flex items-center justify-center w-12 h-12 rounded-full bg-blue-100">
                        <Rotate3d className="h-6 w-6 text-blue-600" />
                      </div>
                    </div>
                    <div className="flex-1">
                      <div className="flex items-center gap-2">
                        <h3 className="font-medium">3D Model Available</h3>
                        <Badge variant="secondary" className="gap-1">
                          <Lock className="h-3 w-3" />
                          Pro
                        </Badge>
                      </div>
                      <p className="text-sm text-gray-600 mt-1">
                        Upgrade to Pro to view the interactive 3D model captured with LiDAR technology.
                      </p>
                    </div>
                    <Link href="/showroom/billing">
                      <Button className="gap-2">
                        <Sparkles className="h-4 w-4" />
                        Upgrade
                      </Button>
                    </Link>
                  </div>
                </CardContent>
              </Card>
            </div>
          ) : has3DModel && can3DView ? (
            // Only 3D model file available and user can view
            <ModelViewer
              glbUrl={measurement.glb_file_url}
              usdzUrl={measurement.usdz_file_url}
              previewImageUrl={measurement.preview_image_url}
              title="3D Room Scan"
              description="Interactive 3D model captured with LiDAR - drag to rotate, scroll to zoom"
            />
          ) : has3DModel && !can3DView ? (
            // Only 3D model available but user can't view - show upgrade prompt
            <Card className="border-blue-200 bg-blue-50/50">
              <CardContent className="py-8">
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
                    This project includes an interactive 3D model captured with LiDAR technology. Upgrade to Pro to view and interact with the 3D scan.
                  </p>
                  <Link href="/showroom/billing">
                    <Button className="gap-2">
                      <Sparkles className="h-4 w-4" />
                      Upgrade to Pro
                    </Button>
                  </Link>
                </div>
              </CardContent>
            </Card>
          ) : hasFloorPlanData ? (
            // Only 2D floor plan data available
            <InteractiveFloorPlan measurements={measurement.measurements} />
          ) : null}
        </div>
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

      {/* Quote Email Preview - AI Generated */}
      {quoteEmail && (
        <QuoteEmailSection quoteEmail={quoteEmail} />
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Main Content */}
        <div className="lg:col-span-2 space-y-6">
          {/* Measurements Summary */}
          <Card>
            <CardHeader>
              <CardTitle>Room Measurements</CardTitle>
              <CardDescription>Key dimensions captured with RoomPlan</CardDescription>
            </CardHeader>
            <CardContent>
              {measurements && measurements.length > 0 ? (
                <div className="space-y-4">
                  {measurements.map((measurement: any) => (
                    <div key={measurement.id}>
                      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                        {measurement.total_linear_ft && (
                          <div className="p-4 bg-gray-50 rounded-lg">
                            <div className="flex items-center gap-2 text-gray-500 mb-1">
                              <Ruler className="h-4 w-4" />
                              <span className="text-sm">Linear Feet</span>
                            </div>
                            <p className="text-2xl font-bold">
                              {measurement.total_linear_ft.toFixed(1)}
                            </p>
                          </div>
                        )}
                        {measurement.total_sq_ft && (
                          <div className="p-4 bg-gray-50 rounded-lg">
                            <div className="flex items-center gap-2 text-gray-500 mb-1">
                              <Square className="h-4 w-4" />
                              <span className="text-sm">Square Feet</span>
                            </div>
                            <p className="text-2xl font-bold">
                              {measurement.total_sq_ft.toFixed(1)}
                            </p>
                          </div>
                        )}
                        {measurement.wall_count && (
                          <div className="p-4 bg-gray-50 rounded-lg">
                            <div className="flex items-center gap-2 text-gray-500 mb-1">
                              <Box className="h-4 w-4" />
                              <span className="text-sm">Walls</span>
                            </div>
                            <p className="text-2xl font-bold">{measurement.wall_count}</p>
                          </div>
                        )}
                        {measurement.door_count !== null && (
                          <div className="p-4 bg-gray-50 rounded-lg">
                            <div className="flex items-center gap-2 text-gray-500 mb-1">
                              <DoorOpen className="h-4 w-4" />
                              <span className="text-sm">Doors</span>
                            </div>
                            <p className="text-2xl font-bold">{measurement.door_count}</p>
                          </div>
                        )}
                        {measurement.measurements?.countertop_summary?.total_area_sqft > 0 && (
                          <div className="p-4 bg-green-50 rounded-lg border border-green-200">
                            <div className="flex items-center gap-2 text-green-700 mb-1">
                              <Square className="h-4 w-4" />
                              <span className="text-sm font-medium">Countertop</span>
                            </div>
                            <p className="text-2xl font-bold text-green-900">
                              {measurement.measurements.countertop_summary.total_area_sqft.toFixed(1)}
                            </p>
                            <p className="text-xs text-green-600 mt-1">sq ft</p>
                          </div>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-gray-500">No measurements recorded</p>
              )}
            </CardContent>
          </Card>

          {/* Product Selections */}
          <Card>
            <CardHeader>
              <CardTitle>Product Selections</CardTitle>
              <CardDescription>Products selected by the customer</CardDescription>
            </CardHeader>
            <CardContent>
              {selections && selections.length > 0 ? (
                <div className="space-y-4">
                  {selections.map((selection: any) => (
                    <div
                      key={selection.id}
                      className="flex items-center gap-4 p-4 border rounded-lg hover:border-gray-300 transition-colors"
                    >
                      {selection.products?.image_url ? (
                        <img
                          src={selection.products.image_url}
                          alt={selection.product_name_snapshot}
                          className="w-16 h-16 object-cover rounded"
                        />
                      ) : (
                        <div className="w-16 h-16 bg-gray-100 rounded flex items-center justify-center">
                          <Box className="h-8 w-8 text-gray-400" />
                        </div>
                      )}
                      <div className="flex-1">
                        <p className="text-sm text-gray-500">
                          {selection.categories?.name}
                        </p>
                        <p className="font-medium">{selection.product_name_snapshot}</p>
                        {selection.customer_notes && (
                          <p className="text-sm text-gray-500 mt-1">
                            Note: {selection.customer_notes}
                          </p>
                        )}
                      </div>
                      <div className="text-right">
                        {selection.product_price_snapshot !== null && (
                          <p className="font-medium">
                            ${selection.product_price_snapshot.toFixed(2)}
                          </p>
                        )}
                        <p className="text-sm text-gray-500">
                          {selection.pricing_unit_snapshot.replace('_', ' ')}
                        </p>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-gray-500">No products selected</p>
              )}
            </CardContent>
          </Card>
        </div>

        {/* Sidebar */}
        <div className="space-y-6">
          {/* Customer Info */}
          <Card>
            <CardHeader>
              <CardTitle>Customer Information</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex items-center gap-3">
                <User className="h-5 w-5 text-gray-400" />
                <div>
                  <p className="font-medium">
                    {project.customer_first_name} {project.customer_last_name}
                  </p>
                </div>
              </div>
              <div className="flex items-center gap-3">
                <Mail className="h-5 w-5 text-gray-400" />
                <a
                  href={`mailto:${project.customer_email}`}
                  className="text-blue-600 hover:underline"
                >
                  {project.customer_email}
                </a>
              </div>
              {project.customer_phone && (
                <div className="flex items-center gap-3">
                  <Phone className="h-5 w-5 text-gray-400" />
                  <a
                    href={`tel:${project.customer_phone}`}
                    className="text-blue-600 hover:underline"
                  >
                    {project.customer_phone}
                  </a>
                </div>
              )}
              {/* Device Info - small text */}
              {(project.device_model || project.ios_version || project.app_version) && (
                <div className="pt-3 mt-3 border-t text-xs text-gray-400 space-y-1">
                  <div className="flex gap-2 flex-wrap">
                    {project.device_model && <span>{project.device_model}</span>}
                    {project.ios_version && <span>iOS {project.ios_version}</span>}
                    {project.app_version && <span>v{project.app_version}</span>}
                  </div>
                </div>
              )}
            </CardContent>
          </Card>

          {/* Timeline */}
          <Card>
            <CardHeader>
              <CardTitle>Timeline</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex items-center gap-3">
                <Calendar className="h-5 w-5 text-gray-400" />
                <div>
                  <p className="text-sm text-gray-500">Submitted</p>
                  <p className="font-medium">
                    {project.submitted_at
                      ? new Date(project.submitted_at).toLocaleString()
                      : '-'}
                  </p>
                </div>
              </div>
              {project.reviewed_at && (
                <div className="flex items-center gap-3">
                  <Calendar className="h-5 w-5 text-gray-400" />
                  <div>
                    <p className="text-sm text-gray-500">Reviewed</p>
                    <p className="font-medium">
                      {new Date(project.reviewed_at).toLocaleString()}
                    </p>
                  </div>
                </div>
              )}
            </CardContent>
          </Card>

          {/* Export & Downloads */}
          {hasDownloadableFiles && (
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <Download className="h-5 w-5" />
                  Export & Downloads
                </CardTitle>
                <CardDescription>Download scan files</CardDescription>
              </CardHeader>
              <CardContent className="space-y-3">
                {hasVisualizationPhotos && (
                  <div className="space-y-3">
                    <div className="text-sm font-medium text-gray-700">
                      Visualization Photos ({visualizationPhotos.length})
                    </div>
                    <div className="grid grid-cols-2 gap-3">
                      {visualizationPhotos.map((photoUrl: string, index: number) => (
                        <div key={index} className="space-y-2">
                          <a
                            href={photoUrl}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="block rounded-lg overflow-hidden border border-gray-200 hover:border-blue-300 transition-colors"
                          >
                            <img
                              src={photoUrl}
                              alt={`Visualization photo ${index + 1}`}
                              className="w-full h-32 object-cover [image-orientation:from-image]"
                            />
                          </a>
                          <a
                            href={photoUrl}
                            download={`visualization_${index + 1}.jpg`}
                            className="flex items-center justify-center gap-2 p-2 rounded-lg border border-gray-200 hover:border-blue-300 hover:bg-blue-50 transition-colors text-xs"
                          >
                            <Download className="h-3 w-3" />
                            Photo {index + 1}
                          </a>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
                {hasVideoFile && (
                  <a
                    href={measurement.video_url}
                    download
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex items-center gap-3 p-3 rounded-lg border border-gray-200 hover:border-blue-300 hover:bg-blue-50 transition-colors group"
                  >
                    <div className="flex-shrink-0 w-10 h-10 rounded-lg bg-red-100 flex items-center justify-center group-hover:bg-red-200 transition-colors">
                      <Video className="h-5 w-5 text-red-600" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-medium text-sm">Scan Video</p>
                      <p className="text-xs text-gray-500">MP4 recording of the scan</p>
                    </div>
                    <Download className="h-4 w-4 text-gray-400 group-hover:text-blue-600" />
                  </a>
                )}
                {hasFloorPlanData && canExportDxf && (
                  <a
                    href={`/api/download-dxf/${id}`}
                    download
                    className="flex items-center gap-3 p-3 rounded-lg border border-gray-200 hover:border-blue-300 hover:bg-blue-50 transition-colors group"
                  >
                    <div className="flex-shrink-0 w-10 h-10 rounded-lg bg-orange-100 flex items-center justify-center group-hover:bg-orange-200 transition-colors">
                      <FileCode className="h-5 w-5 text-orange-600" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-medium text-sm">DXF Floor Plan</p>
                      <p className="text-xs text-gray-500">AutoCAD / 2020 Design format</p>
                    </div>
                    <Download className="h-4 w-4 text-gray-400 group-hover:text-blue-600" />
                  </a>
                )}
                {hasFloorPlanData && !canExportDxf && (
                  <div className="flex items-center gap-3 p-3 rounded-lg border border-gray-200 bg-gray-50">
                    <div className="flex-shrink-0 w-10 h-10 rounded-lg bg-gray-100 flex items-center justify-center">
                      <FileCode className="h-5 w-5 text-gray-400" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <p className="font-medium text-sm text-gray-600">DXF Floor Plan</p>
                        <Badge variant="secondary" className="gap-1 text-xs">
                          <Lock className="h-3 w-3" />
                          Pro
                        </Badge>
                      </div>
                      <p className="text-xs text-gray-500">AutoCAD / 2020 Design format</p>
                    </div>
                  </div>
                )}
                {hasUsdzFile && (
                  <a
                    href={measurement.usdz_file_url}
                    download
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex items-center gap-3 p-3 rounded-lg border border-gray-200 hover:border-blue-300 hover:bg-blue-50 transition-colors group"
                  >
                    <div className="flex-shrink-0 w-10 h-10 rounded-lg bg-purple-100 flex items-center justify-center group-hover:bg-purple-200 transition-colors">
                      <FileBox className="h-5 w-5 text-purple-600" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-medium text-sm">USDZ Model</p>
                      <p className="text-xs text-gray-500">Apple AR Quick Look format</p>
                    </div>
                    <Download className="h-4 w-4 text-gray-400 group-hover:text-blue-600" />
                  </a>
                )}
                {hasGlbFile && (
                  <a
                    href={measurement.glb_file_url}
                    download
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex items-center gap-3 p-3 rounded-lg border border-gray-200 hover:border-blue-300 hover:bg-blue-50 transition-colors group"
                  >
                    <div className="flex-shrink-0 w-10 h-10 rounded-lg bg-green-100 flex items-center justify-center group-hover:bg-green-200 transition-colors">
                      <FileCode className="h-5 w-5 text-green-600" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-medium text-sm">GLB Model</p>
                      <p className="text-xs text-gray-500">Web-compatible 3D format</p>
                    </div>
                    <Download className="h-4 w-4 text-gray-400 group-hover:text-blue-600" />
                  </a>
                )}
              </CardContent>
            </Card>
          )}

          {/* Notes */}
          {project.project_notes && (
            <Card>
              <CardHeader>
                <CardTitle>Customer Notes</CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-gray-600">{project.project_notes}</p>
              </CardContent>
            </Card>
          )}
        </div>
      </div>

      {/* Webhook JSON Payload - Collapsible */}
      {project.webhook_payload && (
        <WebhookPayloadViewer payload={project.webhook_payload as Record<string, unknown>} />
      )}
    </div>
  )
}
