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
  Layers,
  Ruler,
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

      // Get projects
      const { data, error: fetchError } = await supabase
        .from('projects')
        .select('*')
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
    <div className="max-w-full space-y-6">
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
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4 gap-4">
          {filteredProjects.map((project: any) => {
            return (
              <Link
                key={project.id}
                href={`/showroom/projects/${project.id}`}
                className="group"
              >
                <Card className="h-full hover:shadow-md transition-all duration-200 hover:border-blue-400">
                  <CardContent className="p-4">
                    {/* Header: Customer Name + Status */}
                    <div className="flex items-start justify-between gap-2 mb-2">
                      <div className="flex-1 min-w-0">
                        <h3 className="font-semibold truncate group-hover:text-blue-600 transition-colors">
                          {project.customer_first_name} {project.customer_last_name}
                        </h3>
                        <div className="flex items-center gap-2 text-xs text-gray-500">
                          <code className="font-mono">{project.reference_number}</code>
                          <span>|</span>
                          <span>
                            {project.submitted_at
                              ? new Date(project.submitted_at).toLocaleDateString('en-US', {
                                  month: 'short',
                                  day: 'numeric'
                                })
                              : '-'}
                          </span>
                        </div>
                      </div>
                      <Badge className={`${statusColors[project.status]} shrink-0 text-xs`}>
                        {project.status.replace('_', ' ')}
                      </Badge>
                    </div>

                    {/* Email Row */}
                    <div className="text-sm text-gray-600 truncate">
                      {project.customer_email}
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
              Each project includes floor plans, measurements, and product selections.
            </p>
            <div className="flex flex-col sm:flex-row items-center justify-center gap-4 text-sm text-gray-500">
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
