import { createClient } from '@/lib/supabase/server'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { FolderKanban, Rotate3d, Layers, Ruler, User, Calendar, ChevronRight, Box } from 'lucide-react'
import Link from 'next/link'
import { redirect } from 'next/navigation'
import { FloorPlanThumbnail } from '@/components/floor-plan/FloorPlanThumbnail'

export default async function ProjectsPage() {
  const supabase = await createClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  // Get the user's showroom
  const { data: showroomUser } = await supabase
    .from('showroom_users')
    .select('showroom_id')
    .eq('user_id', user.id)
    .single()

  if (!showroomUser) redirect('/login')

  // Get projects with their measurements for preview data
  const { data: projects, error } = await supabase
    .from('projects')
    .select(`
      *,
      project_measurements (
        id,
        usdz_file_url,
        preview_image_url,
        measurements,
        total_linear_ft,
        total_sq_ft
      )
    `)
    .eq('showroom_id', showroomUser.showroom_id)
    .order('submitted_at', { ascending: false })

  const statusColors: Record<string, string> = {
    draft: 'bg-gray-100 text-gray-800',
    submitted: 'bg-blue-100 text-blue-800',
    in_review: 'bg-yellow-100 text-yellow-800',
    quoted: 'bg-purple-100 text-purple-800',
    accepted: 'bg-green-100 text-green-800',
    rejected: 'bg-red-100 text-red-800',
    completed: 'bg-green-100 text-green-800',
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Projects</h1>
        <p className="text-gray-500">View and manage customer room scans and selections</p>
      </div>

      {error ? (
        <Card>
          <CardContent className="py-10 text-center text-red-600">
            Error loading projects: {error.message}
          </CardContent>
        </Card>
      ) : projects && projects.length > 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
          {projects.map((project: any) => {
            // Extract measurement data for preview
            const measurement = project.project_measurements?.[0]
            const hasUsdzFile = measurement?.usdz_file_url
            const hasFloorPlan = measurement?.measurements?.room
            const hasScanData = hasUsdzFile || hasFloorPlan

            return (
              <Link
                key={project.id}
                href={`/showroom/projects/${project.id}`}
                className="group"
              >
                <Card className="h-full overflow-hidden hover:shadow-lg transition-all duration-200 hover:border-blue-400">
                  {/* Visual Preview Section */}
                  <div className="relative h-40 bg-gradient-to-br from-gray-50 to-gray-100 overflow-hidden">
                    {hasUsdzFile && measurement.preview_image_url ? (
                      // 3D model preview image
                      <div className="relative w-full h-full">
                        <img
                          src={measurement.preview_image_url}
                          alt={`${project.project_name} scan preview`}
                          className="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
                        />
                        <div className="absolute inset-0 bg-gradient-to-t from-black/40 to-transparent" />
                        {/* 3D badge */}
                        <div className="absolute top-3 right-3 bg-blue-600 text-white text-xs px-2 py-1 rounded-full font-medium flex items-center gap-1">
                          <Rotate3d className="h-3 w-3" />
                          3D Scan
                        </div>
                      </div>
                    ) : hasFloorPlan ? (
                      // Floor plan thumbnail
                      <div className="relative w-full h-full p-2">
                        <FloorPlanThumbnail
                          measurements={measurement.measurements}
                          className="h-full"
                          showStats={false}
                        />
                        {/* 2D badge */}
                        <div className="absolute top-3 right-3 bg-gray-700 text-white text-xs px-2 py-1 rounded-full font-medium flex items-center gap-1">
                          <Layers className="h-3 w-3" />
                          Floor Plan
                        </div>
                      </div>
                    ) : (
                      // No scan data placeholder
                      <div className="flex flex-col items-center justify-center h-full">
                        <Box className="h-12 w-12 text-gray-300 mb-2" />
                        <span className="text-sm text-gray-400">No scan data</span>
                      </div>
                    )}

                    {/* Measurements overlay */}
                    {hasScanData && (measurement?.total_linear_ft || measurement?.total_sq_ft) && (
                      <div className="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/70 to-transparent p-3 pt-8">
                        <div className="flex items-center gap-4 text-white text-sm">
                          {measurement.total_sq_ft && (
                            <span className="flex items-center gap-1.5">
                              <Ruler className="h-3.5 w-3.5" />
                              {measurement.total_sq_ft.toFixed(0)} sq ft
                            </span>
                          )}
                          {measurement.total_linear_ft && (
                            <span className="flex items-center gap-1.5">
                              <Ruler className="h-3.5 w-3.5" />
                              {measurement.total_linear_ft.toFixed(0)} linear ft
                            </span>
                          )}
                        </div>
                      </div>
                    )}
                  </div>

                  {/* Project Info Section */}
                  <CardContent className="p-4">
                    <div className="flex items-start justify-between mb-3">
                      <div className="flex-1 min-w-0">
                        <h3 className="font-semibold text-lg truncate group-hover:text-blue-600 transition-colors">
                          {project.project_name}
                        </h3>
                        <code className="text-xs px-1.5 py-0.5 bg-gray-100 rounded text-gray-600 font-mono">
                          {project.reference_number}
                        </code>
                      </div>
                      <Badge className={`${statusColors[project.status]} shrink-0 ml-2`}>
                        {project.status.replace('_', ' ')}
                      </Badge>
                    </div>

                    <div className="space-y-2 text-sm text-gray-600">
                      {/* Customer */}
                      <div className="flex items-center gap-2">
                        <User className="h-4 w-4 text-gray-400" />
                        <span className="truncate">
                          {project.customer_first_name} {project.customer_last_name}
                        </span>
                      </div>

                      {/* Date */}
                      <div className="flex items-center gap-2">
                        <Calendar className="h-4 w-4 text-gray-400" />
                        <span>
                          {project.submitted_at
                            ? new Date(project.submitted_at).toLocaleDateString('en-US', {
                                month: 'short',
                                day: 'numeric',
                                year: 'numeric'
                              })
                            : 'Not submitted'}
                        </span>
                      </div>
                    </div>

                    {/* View button */}
                    <div className="mt-4 pt-3 border-t flex items-center justify-between">
                      <span className="text-sm text-gray-500">
                        {project.customer_email}
                      </span>
                      <Button
                        variant="ghost"
                        size="sm"
                        className="text-blue-600 hover:text-blue-700 hover:bg-blue-50 -mr-2"
                      >
                        View
                        <ChevronRight className="h-4 w-4 ml-1" />
                      </Button>
                    </div>
                  </CardContent>
                </Card>
              </Link>
            )
          })}
        </div>
      ) : (
        <Card>
          <CardContent className="py-16 text-center">
            <div className="w-20 h-20 rounded-full bg-gray-100 flex items-center justify-center mx-auto mb-6">
              <FolderKanban className="h-10 w-10 text-gray-400" />
            </div>
            <h3 className="text-xl font-medium mb-2">No projects yet</h3>
            <p className="text-gray-500 max-w-md mx-auto mb-6">
              Projects will appear here when customers submit room scans from the iOS app.
              Each project includes the 3D scan, measurements, and product selections.
            </p>
            <div className="flex flex-col sm:flex-row items-center justify-center gap-4 text-sm text-gray-500">
              <div className="flex items-center gap-2">
                <Rotate3d className="h-5 w-5 text-blue-500" />
                <span>3D Room Scans</span>
              </div>
              <div className="flex items-center gap-2">
                <Layers className="h-5 w-5 text-gray-500" />
                <span>Floor Plans</span>
              </div>
              <div className="flex items-center gap-2">
                <Ruler className="h-5 w-5 text-green-500" />
                <span>Measurements</span>
              </div>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
