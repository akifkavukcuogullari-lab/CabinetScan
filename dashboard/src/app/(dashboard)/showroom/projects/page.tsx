'use client'

import { useState, useEffect, useMemo, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
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
  LayoutGrid,
  List,
  ArrowUpDown,
  Lock,
  TrendingUp,
  Paintbrush,
} from 'lucide-react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useSubscriptionContext } from '@/contexts/subscription-context'

import { PROJECT_STATUSES, getStatusColor, getStatusLabel, mapDesignStatus } from '@/lib/project-status'

const statusFilterOptions = [
  { value: 'all', label: 'All Statuses' },
  ...PROJECT_STATUSES.map(s => ({ value: s.value, label: s.label })),
]

function DesignStatusBadge({ status }: { status: string }) {
  const config: Record<string, { label: string; className: string }> = {
    pending: { label: 'Design Requested', className: 'bg-orange-100 text-orange-700 border-orange-200' },
    accepted: { label: 'In Design', className: 'bg-blue-100 text-blue-700 border-blue-200' },
    in_progress: { label: 'In Design', className: 'bg-blue-100 text-blue-700 border-blue-200' },
    delivered: { label: 'Design Delivered', className: 'bg-purple-100 text-purple-700 border-purple-200' },
    approved: { label: 'Design Approved', className: 'bg-green-100 text-green-700 border-green-200' },
    revision_requested: { label: 'Revision Requested', className: 'bg-yellow-100 text-yellow-700 border-yellow-200' },
    completed: { label: 'Design Complete', className: 'bg-green-100 text-green-700 border-green-200' },
    canceled: { label: 'Design Canceled', className: 'bg-gray-100 text-gray-600 border-gray-200' },
  }

  const entry = config[status]
  if (!entry || status === 'canceled') return null

  return (
    <span className={`inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full border ${entry.className}`}>
      <Paintbrush className="h-3 w-3" />
      {entry.label}
    </span>
  )
}

export default function ProjectsPage() {
  const router = useRouter()
  const supabase = createClient()
  const { usage, loading: subscriptionLoading } = useSubscriptionContext()

  const [loading, setLoading] = useState(true)
  const [projects, setProjects] = useState<any[]>([])
  const [designStatuses, setDesignStatuses] = useState<Record<string, string>>({})
  const [error, setError] = useState<string | null>(null)

  // Check if ANY plan limit is exceeded (blocks new projects)
  const exceededLimits = {
    projects: usage.projects.exceeded && !usage.projects.unlimited,
    products: usage.products.exceeded && !usage.products.unlimited,
    storage: usage.storage.exceeded && !usage.storage.unlimited,
    teamMembers: usage.teamMembers.exceeded && !usage.teamMembers.unlimited,
  }
  const hasAnyLimitExceeded = Object.values(exceededLimits).some(Boolean)

  // Get the exceeded limit details for display
  const getExceededLimitMessage = () => {
    const messages: string[] = []
    if (exceededLimits.projects) {
      messages.push(`Projects: ${usage.projects.current}/${usage.projects.limit}`)
    }
    if (exceededLimits.products) {
      messages.push(`Products: ${usage.products.current}/${usage.products.limit}`)
    }
    if (exceededLimits.storage) {
      messages.push(`Storage: ${usage.storage.current}GB/${usage.storage.limit}GB`)
    }
    if (exceededLimits.teamMembers) {
      messages.push(`Team Members: ${usage.teamMembers.current}/${usage.teamMembers.limit}`)
    }
    return messages
  }

  // Filter state
  const [searchQuery, setSearchQuery] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')

  // View mode state
  const [viewMode, setViewMode] = useState<'grid' | 'table'>('grid')
  const [sortColumn, setSortColumn] = useState<'name' | 'email' | 'date' | 'status' | 'reference'>('date')
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('desc')

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
        .order('created_at', { ascending: false })

      if (fetchError) {
        setError(fetchError.message)
      } else {
        setProjects(data || [])

        // Fetch design request statuses for all projects
        if (data && data.length > 0) {
          const projectIds = data.map((p: any) => p.id)
          const { data: designRequests } = await supabase
            .from('design_requests')
            .select('project_id, status')
            .in('project_id', projectIds)

          if (designRequests) {
            const statusMap: Record<string, string> = {}
            designRequests.forEach((dr: any) => {
              statusMap[dr.project_id] = dr.status
            })
            setDesignStatuses(statusMap)
          }
        }
      }
      setLoading(false)
    }

    loadProjects()
  }, [supabase, router])

  // Load view preference from localStorage
  useEffect(() => {
    const saved = localStorage.getItem('projects-view-preference')
    if (saved === 'grid' || saved === 'table') {
      setViewMode(saved)
    }
  }, [])

  // Handle view mode change with localStorage persistence
  const handleViewChange = (mode: 'grid' | 'table') => {
    setViewMode(mode)
    localStorage.setItem('projects-view-preference', mode)
  }

  // Handle sort column change
  const handleSort = (column: 'name' | 'email' | 'date' | 'status' | 'reference') => {
    if (sortColumn === column) {
      // Toggle direction if same column
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc')
    } else {
      // New column, default to descending (except for name/email which default to ascending)
      setSortColumn(column)
      setSortDirection(column === 'name' || column === 'email' ? 'asc' : 'desc')
    }
  }

  // Helper to get effective status (merges design status into project status)
  const getEffectiveStatus = useCallback((project: any) => {
    const ds = designStatuses[project.id]
    if (ds && ds !== 'canceled') {
      return mapDesignStatus(ds) || project.status
    }
    return project.status
  }, [designStatuses])

  // Filter projects based on search and status
  const filteredProjects = useMemo(() => {
    return projects.filter((project) => {
      // Status filter
      if (statusFilter !== 'all' && getEffectiveStatus(project) !== statusFilter) {
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

  // Count projects by effective status for filter badges
  const statusCounts = useMemo(() => {
    const counts: Record<string, number> = { all: projects.length }
    projects.forEach((p) => {
      const effective = getEffectiveStatus(p)
      counts[effective] = (counts[effective] || 0) + 1
    })
    return counts
  }, [projects, getEffectiveStatus])

  // Sort projects for table view
  const sortedProjects = useMemo(() => {
    if (viewMode !== 'table') return filteredProjects

    const sorted = [...filteredProjects]
    sorted.sort((a, b) => {
      let compare = 0

      switch (sortColumn) {
        case 'name':
          const nameA = `${a.customer_first_name || ''} ${a.customer_last_name || ''}`.toLowerCase()
          const nameB = `${b.customer_first_name || ''} ${b.customer_last_name || ''}`.toLowerCase()
          compare = nameA.localeCompare(nameB)
          break
        case 'email':
          compare = (a.customer_email || '').localeCompare(b.customer_email || '')
          break
        case 'date':
          const dateA = new Date(a.submitted_at || a.created_at).getTime()
          const dateB = new Date(b.submitted_at || b.created_at).getTime()
          compare = dateA - dateB
          break
        case 'status':
          compare = (a.status || '').localeCompare(b.status || '')
          break
        case 'reference':
          compare = (a.reference_number || '').localeCompare(b.reference_number || '')
          break
      }

      return sortDirection === 'asc' ? compare : -compare
    })
    return sorted
  }, [filteredProjects, viewMode, sortColumn, sortDirection])

  const clearFilters = () => {
    setSearchQuery('')
    setStatusFilter('all')
  }

  const hasActiveFilters = searchQuery.trim() || statusFilter !== 'all'

  if (loading || subscriptionLoading) {
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

      {/* Warning Banner when limits exceeded - new submissions blocked */}
      {hasAnyLimitExceeded && (
        <Card className="border-amber-300 bg-amber-50">
          <CardContent className="py-4">
            <div className="flex items-start gap-4">
              <div className="flex-shrink-0">
                <Lock className="h-6 w-6 text-amber-600" />
              </div>
              <div className="flex-1">
                <h3 className="font-medium text-amber-800">New Submissions Paused</h3>
                <p className="text-sm text-amber-700 mt-1">
                  Plan limits exceeded. New customer submissions from the iOS app are blocked until resolved.
                </p>
                <div className="flex flex-wrap gap-2 mt-2">
                  {getExceededLimitMessage().map((msg, idx) => (
                    <Badge key={idx} variant="outline" className="border-amber-400 text-amber-800 text-xs">
                      {msg}
                    </Badge>
                  ))}
                </div>
              </div>
              <Button asChild size="sm" className="flex-shrink-0 bg-amber-600 hover:bg-amber-700">
                <Link href="/showroom/billing">
                  <TrendingUp className="h-4 w-4 mr-1" />
                  Upgrade
                </Link>
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

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
                  {statusFilterOptions.map((option) => (
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

            {/* View Mode Toggle */}
            <div className="flex gap-1 border rounded-lg p-1">
              <Button
                variant={viewMode === 'grid' ? 'secondary' : 'ghost'}
                size="sm"
                onClick={() => handleViewChange('grid')}
                className="gap-2"
              >
                <LayoutGrid className="h-4 w-4" />
                <span className="hidden sm:inline">Grid</span>
              </Button>
              <Button
                variant={viewMode === 'table' ? 'secondary' : 'ghost'}
                size="sm"
                onClick={() => handleViewChange('table')}
                className="gap-2"
              >
                <List className="h-4 w-4" />
                <span className="hidden sm:inline">Table</span>
              </Button>
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
                <Badge className={getStatusColor(statusFilter)}>
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
        viewMode === 'grid' ? (
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
                              {new Date(project.submitted_at || project.created_at).toLocaleDateString('en-US', {
                                    month: 'short',
                                    day: 'numeric'
                                  })}
                            </span>
                          </div>
                        </div>
                        <Badge className={`${getStatusColor(project.status)} shrink-0 text-xs`}>
                          {project.status.replace('_', ' ')}
                        </Badge>
                      </div>

                      {/* Email Row */}
                      <div className="text-sm text-gray-600 truncate">
                        {project.customer_email}
                      </div>

                      {/* Design Status Indicator */}
                      {designStatuses[project.id] && (
                        <div className="mt-2">
                          <DesignStatusBadge status={designStatuses[project.id]} />
                        </div>
                      )}
                    </CardContent>
                  </Card>
                </Link>
              )
            })}
          </div>
        ) : (
          <Card>
            <CardContent className="p-0">
              <div className="overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead
                        className="cursor-pointer hover:bg-muted/50"
                        onClick={() => handleSort('reference')}
                      >
                        <div className="flex items-center gap-2">
                          Reference
                          <ArrowUpDown className="h-4 w-4" />
                        </div>
                      </TableHead>
                      <TableHead
                        className="cursor-pointer hover:bg-muted/50"
                        onClick={() => handleSort('name')}
                      >
                        <div className="flex items-center gap-2">
                          Customer Name
                          <ArrowUpDown className="h-4 w-4" />
                        </div>
                      </TableHead>
                      <TableHead
                        className="cursor-pointer hover:bg-muted/50"
                        onClick={() => handleSort('email')}
                      >
                        <div className="flex items-center gap-2">
                          Email
                          <ArrowUpDown className="h-4 w-4" />
                        </div>
                      </TableHead>
                      <TableHead
                        className="cursor-pointer hover:bg-muted/50"
                        onClick={() => handleSort('date')}
                      >
                        <div className="flex items-center gap-2">
                          Date Submitted
                          <ArrowUpDown className="h-4 w-4" />
                        </div>
                      </TableHead>
                      <TableHead
                        className="cursor-pointer hover:bg-muted/50"
                        onClick={() => handleSort('status')}
                      >
                        <div className="flex items-center gap-2">
                          Status
                          <ArrowUpDown className="h-4 w-4" />
                        </div>
                      </TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {sortedProjects.map((project: any) => (
                      <TableRow
                        key={project.id}
                        className="cursor-pointer hover:bg-muted/50"
                        onClick={() => router.push(`/showroom/projects/${project.id}`)}
                      >
                        <TableCell className="font-mono text-sm">
                          {project.reference_number}
                        </TableCell>
                        <TableCell className="font-medium">
                          {project.customer_first_name} {project.customer_last_name}
                        </TableCell>
                        <TableCell className="text-gray-600">
                          {project.customer_email}
                        </TableCell>
                        <TableCell className="text-gray-600">
                          {project.submitted_at
                            ? new Date(project.submitted_at).toLocaleDateString('en-US', {
                                year: 'numeric',
                                month: 'short',
                                day: 'numeric',
                              })
                            : '-'}
                        </TableCell>
                        <TableCell>
                          {(() => {
                            const effective = getEffectiveStatus(project)
                            return (
                              <Badge className={getStatusColor(effective)}>
                                {getStatusLabel(effective)}
                              </Badge>
                            )
                          })()}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            </CardContent>
          </Card>
        )
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
