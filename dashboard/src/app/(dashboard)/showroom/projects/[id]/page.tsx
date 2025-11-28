import { createClient } from '@/lib/supabase/server'
import { notFound, redirect } from 'next/navigation'
import Link from 'next/link'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { FloorPlanViewer } from '@/components/floor-plan/FloorPlanViewer'
import { ModelViewer } from '@/components/3d-viewer/ModelViewer'
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
  Download,
  Layers,
  Rotate3d,
} from 'lucide-react'

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
  }

  // Extract scan data
  const measurement = measurements && measurements.length > 0 ? measurements[0] : null
  const hasUsdzFile = measurement?.usdz_file_url
  const hasFloorPlan = measurement?.measurements?.room
  const hasScanData = hasUsdzFile || hasFloorPlan

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

          {hasUsdzFile && hasFloorPlan ? (
            // Both 3D and 2D available - show tabs
            <Tabs defaultValue="3d" className="w-full">
              <TabsList className="mb-4">
                <TabsTrigger value="3d" className="flex items-center gap-2">
                  <Rotate3d className="h-4 w-4" />
                  3D Model
                </TabsTrigger>
                <TabsTrigger value="2d" className="flex items-center gap-2">
                  <Layers className="h-4 w-4" />
                  2D Floor Plan
                </TabsTrigger>
              </TabsList>

              <TabsContent value="3d" className="mt-0">
                <ModelViewer
                  usdzUrl={measurement.usdz_file_url}
                  previewImageUrl={measurement.preview_image_url}
                  title="3D Room Scan"
                  description="Interactive 3D model captured with LiDAR - drag to rotate, scroll to zoom"
                />
              </TabsContent>

              <TabsContent value="2d" className="mt-0">
                <FloorPlanViewer measurements={measurement.measurements} />
              </TabsContent>
            </Tabs>
          ) : hasUsdzFile ? (
            // Only 3D available
            <ModelViewer
              usdzUrl={measurement.usdz_file_url}
              previewImageUrl={measurement.preview_image_url}
              title="3D Room Scan"
              description="Interactive 3D model captured with LiDAR - drag to rotate, scroll to zoom"
            />
          ) : hasFloorPlan ? (
            // Only 2D available
            <FloorPlanViewer measurements={measurement.measurements} />
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

                      {measurement.usdz_file_url && (
                        <div className="mt-4 p-3 bg-blue-50 rounded-lg border border-blue-200">
                          <div className="flex items-center justify-between">
                            <div className="flex items-center gap-2">
                              <Rotate3d className="h-5 w-5 text-blue-600" />
                              <span className="text-sm font-medium text-blue-900">3D Model Available</span>
                            </div>
                            <a
                              href={measurement.usdz_file_url}
                              download
                              className="inline-flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
                            >
                              <Download className="h-4 w-4" />
                              Download USDZ
                            </a>
                          </div>
                          <p className="text-xs text-blue-600 mt-2">
                            Open in Apple AR Quick Look, Reality Composer, or any USDZ-compatible viewer
                          </p>
                        </div>
                      )}
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

          {/* Device Info */}
          {(project.device_model || project.ios_version || project.app_version) && (
            <Card>
              <CardHeader>
                <CardTitle>Device Info</CardTitle>
              </CardHeader>
              <CardContent className="space-y-2 text-sm">
                {project.device_model && (
                  <div className="flex justify-between">
                    <span className="text-gray-500">Device</span>
                    <span>{project.device_model}</span>
                  </div>
                )}
                {project.ios_version && (
                  <div className="flex justify-between">
                    <span className="text-gray-500">iOS Version</span>
                    <span>{project.ios_version}</span>
                  </div>
                )}
                {project.app_version && (
                  <div className="flex justify-between">
                    <span className="text-gray-500">App Version</span>
                    <span>{project.app_version}</span>
                  </div>
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
    </div>
  )
}
