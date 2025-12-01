'use client'

import { useState, useEffect, useMemo } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  FolderKanban,
  Rotate3d,
  Layers,
  Ruler,
  User,
  Calendar,
  ChevronRight,
  Box,
  Search,
  Filter,
  X,
  Loader2,
} from 'lucide-react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'

const statusOptions = [
  { value: 'all', label: 'All Statuses' },
  { value: 'draft', label: 'Draft' },
  { value: 'submitted', label: 'Submitted' },
  { value: 'in_review', label: 'In Review' },
  { value: 'quoted', label: 'Quoted' },
  { value: 'accepted', label: 'Accepted' },
  { value: 'rejected', label: 'Rejected' },
  { value: 'completed', label: 'Completed' },
]

const statusColors: Record<string, string> = {
  draft: 'bg-gray-100 text-gray-800',
  submitted: 'bg-blue-100 text-blue-800',
  in_review: 'bg-yellow-100 text-yellow-800',
  quoted: 'bg-purple-100 text-purple-800',
  accepted: 'bg-green-100 text-green-800',
  rejected: 'bg-red-100 text-red-800',
  completed: 'bg-green-100 text-green-800',
}

export default function ProjectsPage() {
  const router = useRouter()
  const supabase = createClient()

  const [loading, setLoading] = useState(true)
  const [projects, setProjects] = useState<any[]>([])
  const [error, setError] = useState<string | null>(null)

  // Filter state
  const [searchQuery, setSearchQuery] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')

  useEffect(() => {
    async function loadProjects() {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) {
        router.push('/login')
        return
      }

      // Get the user's showroom
      const { data: showroomUser } = await supabase
        .from('showroom_users')
        .select('showroom_id')
        .eq('user_id', user.id)
        .single()

      if (!showroomUser) {
        router.push('/login')
        return
      }

      // Get projects with their measurements
      const { data, error: fetchError } = await supabase
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

      if (fetchError) {
        setError(fetchError.message)
      } else {
        setProjects(data || [])
      }
      setLoading(false)
    }

    loadProjects()
  }, [supabase, router])

  // Filter projects based on search and status
  const filteredProjects = useMemo(() => {
    return projects.filter((project) => {
      // Status filter
      if (statusFilter !== 'all' && project.status !== statusFilter) {
        return false
      }

      // Search filter (customer name, email, project name, reference number)
      if (searchQuery.trim()) {
        const query = searchQuery.toLowerCase()
        const customerName = `${project.customer_first_name || ''} ${project.customer_last_name || ''}`.toLowerCase()
        const email = (project.customer_email || '').toLowerCase()
        const projectName = (project.project_name || '').toLowerCase()
        const refNumber = (project.reference_number || '').toLowerCase()

        if (
          !customerName.includes(query) &&
          !email.includes(query) &&
          !projectName.includes(query) &&
          !refNumber.includes(query)
        ) {
          return false
        }
      }

      return true
    })
  }, [projects, searchQuery, statusFilter])

  // Count projects by status for filter badges
  const statusCounts = useMemo(() => {
    const counts: Record<string, number> = { all: projects.length }
    projects.forEach((p) => {
      counts[p.status] = (counts[p.status] || 0) + 1
    })
    return counts
  }, [projects])

  const clearFilters = () => {
    setSearchQuery('')
    setStatusFilter('all')
  }

  const hasActiveFilters = searchQuery.trim() || statusFilter !== 'all'

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <Loader2 className="h-8 w-8 animate-spin text-blue-600" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Projects</h1>
        <p className="text-gray-500">View and manage customer room scans and selections</p>
      </div>

      {/* Filters Section */}
      <Card>
        <CardContent className="p-4">
          <div className="flex flex-col sm:flex-row gap-4">
            {/* Search Input */}
            <div className="relative flex-1">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
              <Input
                placeholder="Search by customer name, email, or reference..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="pl-10"
              />
            </div>

            {/* Status Filter */}
            <div className="flex items-center gap-2">
              <Filter className="h-4 w-4 text-gray-400 hidden sm:block" />
              <Select value={statusFilter} onValueChange={setStatusFilter}>
                <SelectTrigger className="w-full sm:w-[180px]">
                  <SelectValue placeholder="Filter by status" />
                </SelectTrigger>
                <SelectContent>
                  {statusOptions.map((option) => (
                    <SelectItem key={option.value} value={option.value}>
                      <div className="flex items-center justify-between w-full">
                        <span>{option.label}</span>
                        {statusCounts[option.value] !== undefined && (
                          <Badge variant="secondary" className="ml-2 text-xs">
                            {statusCounts[option.value]}
                          </Badge>
                        )}
                      </div>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            {/* Clear Filters */}
            {hasActiveFilters && (
              <Button
                variant="ghost"
                size="sm"
                onClick={clearFilters}
                className="text-gray-500 hover:text-gray-700"
              >
                <X className="h-4 w-4 mr-1" />
                Clear
              </Button>
            )}
          </div>

          {/* Active filters summary */}
          {hasActiveFilters && (
            <div className="mt-3 pt-3 border-t flex items-center gap-2 text-sm text-gray-600">
              <span>Showing {filteredProjects.length} of {projects.length} projects</span>
              {statusFilter !== 'all' && (
                <Badge className={statusColors[statusFilter]}>
                  {statusFilter.replace('_', ' ')}
                </Badge>
              )}
            </div>
          )}
        </CardContent>
      </Card>

      {error ? (
        <Card>
          <CardContent className="py-10 text-center text-red-600">
            Error loading projects: {error}
          </CardContent>
        </Card>
      ) : filteredProjects.length > 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
          {filteredProjects.map((project: any) => {
            // Extract measurement data for preview
            const measurement = project.project_measurements?.[0]
            const hasUsdzFile = measurement?.usdz_file_url
            const hasFloorPlanImage = measurement?.preview_image_url
            const hasScanData = hasUsdzFile || hasFloorPlanImage

            return (
              <Link
                key={project.id}
                href={`/showroom/projects/${project.id}`}
                className="group"
              >
                <Card className="h-full overflow-hidden hover:shadow-lg transition-all duration-200 hover:border-blue-400">
                  {/* Visual Preview Section */}
                  <div className="relative h-40 bg-gradient-to-br from-gray-50 to-gray-100 overflow-hidden">
                    {hasUsdzFile ? (
                      // 3D model preview - use floor plan image as preview
                      <div className="relative w-full h-full">
                        {hasFloorPlanImage ? (
                          <img
                            src={measurement.preview_image_url}
                            alt={`${project.project_name} scan preview`}
                            className="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
                          />
                        ) : (
                          <div className="flex items-center justify-center h-full bg-blue-50">
                            <Rotate3d className="h-12 w-12 text-blue-300" />
                          </div>
                        )}
                        <div className="absolute inset-0 bg-gradient-to-t from-black/40 to-transparent" />
                        {/* 3D badge */}
                        <div className="absolute top-3 right-3 bg-blue-600 text-white text-xs px-2 py-1 rounded-full font-medium flex items-center gap-1">
                          <Rotate3d className="h-3 w-3" />
                          3D Scan
                        </div>
                      </div>
                    ) : hasFloorPlanImage ? (
                      // 2D floor plan image
                      <div className="relative w-full h-full">
                        <img
                          src={measurement.preview_image_url}
                          alt={`${project.project_name} floor plan`}
                          className="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
                        />
                        <div className="absolute inset-0 bg-gradient-to-t from-black/40 to-transparent" />
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
      ) : projects.length > 0 ? (
        // Has projects but none match filters
        <Card>
          <CardContent className="py-16 text-center">
            <div className="w-20 h-20 rounded-full bg-gray-100 flex items-center justify-center mx-auto mb-6">
              <Search className="h-10 w-10 text-gray-400" />
            </div>
            <h3 className="text-xl font-medium mb-2">No matching projects</h3>
            <p className="text-gray-500 max-w-md mx-auto mb-6">
              No projects match your current filters. Try adjusting your search or status filter.
            </p>
            <Button variant="outline" onClick={clearFilters}>
              Clear Filters
            </Button>
          </CardContent>
        </Card>
      ) : (
        // No projects at all
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
