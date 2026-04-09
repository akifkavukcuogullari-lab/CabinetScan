'use client'

import { useState, useEffect, useMemo } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Badge } from '@/components/ui/badge'
import { Input } from '@/components/ui/input'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Loader2, Search, Phone as PhoneIcon, Filter, X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import type { VoiceAgentLog, SimplifiedOutcome } from '@/types/voice-agent'
import { OUTCOME_COLORS, OUTCOME_LABELS } from '@/types/voice-agent'

interface VoiceAgentActivityListProps {
  showroomId: string
  onSelectProject: (projectId: string) => void
}

interface ProjectWithLogs {
  project_id: string
  customer_name: string
  reference_number: string
  customer_phone: string | null
  latest_outcome: SimplifiedOutcome | null
  attempt_count: number
  flow_status: string
  last_activity: string
}

const FLOW_STATUS_COLORS: Record<string, string> = {
  active: 'bg-blue-100 text-blue-800',
  waiting: 'bg-yellow-100 text-yellow-800',
  completed: 'bg-green-100 text-green-800',
  stopped: 'bg-gray-100 text-gray-800',
}

function formatRelativeTime(dateStr: string): string {
  const now = new Date()
  const date = new Date(dateStr)
  const diffMs = now.getTime() - date.getTime()
  const diffSeconds = Math.floor(diffMs / 1000)
  const diffMinutes = Math.floor(diffSeconds / 60)
  const diffHours = Math.floor(diffMinutes / 60)
  const diffDays = Math.floor(diffHours / 24)

  if (diffSeconds < 60) return 'Just now'
  if (diffMinutes < 60) return `${diffMinutes}m ago`
  if (diffHours < 24) return `${diffHours}h ago`
  if (diffDays === 1) return 'Yesterday'
  if (diffDays < 7) return `${diffDays}d ago`
  return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' })
}

export function VoiceAgentActivityList({
  showroomId,
  onSelectProject,
}: VoiceAgentActivityListProps) {
  const supabase = createClient()
  const [loading, setLoading] = useState(true)
  const [projects, setProjects] = useState<ProjectWithLogs[]>([])
  const [search, setSearch] = useState('')
  const [outcomeFilter, setOutcomeFilter] = useState<string>('all')
  const [flowStatusFilter, setFlowStatusFilter] = useState<string>('all')
  const [dateFilter, setDateFilter] = useState<string>('all')

  useEffect(() => {
    async function loadActivity() {
      setLoading(true)
      try {
        const { data, error } = await supabase
          .from('voice_agent_logs')
          .select(
            '*, projects(id, reference_number, customer_first_name, customer_last_name, customer_phone)'
          )
          .eq('showroom_id', showroomId)
          .order('created_at', { ascending: false })

        if (error) throw error
        if (!data || data.length === 0) {
          setProjects([])
          return
        }

        // Group by project_id and take the latest log per project
        const projectMap = new Map<string, ProjectWithLogs>()

        for (const log of data) {
          const pid = log.project_id
          const proj = (log as Record<string, unknown>).projects as {
            id: string
            reference_number: string
            customer_first_name: string
            customer_last_name: string
            customer_phone: string | null
          } | null

          if (!proj) continue

          const existing = projectMap.get(pid)
          if (!existing) {
            projectMap.set(pid, {
              project_id: pid,
              customer_name: `${proj.customer_first_name} ${proj.customer_last_name}`.trim(),
              reference_number: proj.reference_number || '',
              customer_phone: proj.customer_phone || log.customer_phone,
              latest_outcome: log.outcome as SimplifiedOutcome | null,
              attempt_count: 1,
              flow_status: log.flow_status,
              last_activity: log.created_at,
            })
          } else {
            existing.attempt_count += 1
            // The first log we encounter is the latest (ordered desc)
          }
        }

        setProjects(Array.from(projectMap.values()))
      } catch (error) {
        console.error('Error loading voice agent activity:', error)
      } finally {
        setLoading(false)
      }
    }

    loadActivity()
  }, [supabase, showroomId])

  const hasActiveFilters = outcomeFilter !== 'all' || flowStatusFilter !== 'all' || dateFilter !== 'all'

  const filtered = useMemo(() => {
    let result = projects

    // Search filter
    if (search.trim()) {
      const q = search.toLowerCase()
      result = result.filter(
        (p) =>
          p.customer_name.toLowerCase().includes(q) ||
          p.reference_number.toLowerCase().includes(q)
      )
    }

    // Outcome filter
    if (outcomeFilter !== 'all') {
      result = result.filter((p) => p.latest_outcome === outcomeFilter)
    }

    // Flow status filter
    if (flowStatusFilter !== 'all') {
      result = result.filter((p) => p.flow_status === flowStatusFilter)
    }

    // Date filter
    if (dateFilter !== 'all') {
      const now = new Date()
      const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate())
      const startOfYesterday = new Date(startOfToday.getTime() - 86400000)
      const startOfWeek = new Date(startOfToday.getTime() - startOfToday.getDay() * 86400000)
      const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1)

      result = result.filter((p) => {
        const d = new Date(p.last_activity)
        switch (dateFilter) {
          case 'today': return d >= startOfToday
          case 'yesterday': return d >= startOfYesterday && d < startOfToday
          case 'this_week': return d >= startOfWeek
          case 'this_month': return d >= startOfMonth
          default: return true
        }
      })
    }

    return result
  }, [projects, search, outcomeFilter, flowStatusFilter, dateFilter])

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
      </div>
    )
  }

  if (projects.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-16 text-center">
        <div className="p-3 bg-gray-100 rounded-full mb-3">
          <PhoneIcon className="h-8 w-8 text-gray-400" />
        </div>
        <h3 className="text-lg font-semibold text-gray-900">
          No voice agent activity yet
        </h3>
        <p className="text-sm text-gray-500 mt-1 max-w-sm">
          When the voice agent makes calls to customers, their activity will appear
          here.
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {/* Search bar */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
        <Input
          placeholder="Search by customer name or reference number..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="pl-9"
        />
      </div>

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex items-center gap-1.5 text-sm text-gray-500">
          <Filter className="h-3.5 w-3.5" />
          Filters:
        </div>

        <select
          value={dateFilter}
          onChange={(e) => setDateFilter(e.target.value)}
          className="text-sm border rounded-md px-2 py-1.5 bg-white text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500"
        >
          <option value="all">All Time</option>
          <option value="today">Today</option>
          <option value="yesterday">Yesterday</option>
          <option value="this_week">This Week</option>
          <option value="this_month">This Month</option>
        </select>

        <select
          value={outcomeFilter}
          onChange={(e) => setOutcomeFilter(e.target.value)}
          className="text-sm border rounded-md px-2 py-1.5 bg-white text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500"
        >
          <option value="all">All Outcomes</option>
          <option value="no_answer">No Answer</option>
          <option value="line_busy">Line Busy</option>
          <option value="voicemail">Voicemail</option>
          <option value="ghosted">Ghosted</option>
          <option value="interested">Interested</option>
          <option value="not_interested">Not Interested</option>
          <option value="link_sent">Link Sent</option>
          <option value="callback_requested">Callback Requested</option>
          <option value="hung_up_early">Hung Up Early</option>
          <option value="technical_error">Technical Error</option>
        </select>

        <select
          value={flowStatusFilter}
          onChange={(e) => setFlowStatusFilter(e.target.value)}
          className="text-sm border rounded-md px-2 py-1.5 bg-white text-gray-700 focus:outline-none focus:ring-2 focus:ring-blue-500"
        >
          <option value="all">All Statuses</option>
          <option value="active">Active</option>
          <option value="waiting">Waiting</option>
          <option value="completed">Completed</option>
          <option value="stopped">Stopped</option>
        </select>

        {hasActiveFilters && (
          <Button
            variant="ghost"
            size="sm"
            className="h-7 px-2 text-xs text-gray-500"
            onClick={() => {
              setOutcomeFilter('all')
              setFlowStatusFilter('all')
              setDateFilter('all')
            }}
          >
            <X className="h-3 w-3 mr-1" />
            Clear
          </Button>
        )}

        <span className="text-xs text-gray-400 ml-auto">
          {filtered.length} of {projects.length} projects
        </span>
      </div>

      {/* Table */}
      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Customer</TableHead>
              <TableHead>Reference #</TableHead>
              <TableHead className="hidden sm:table-cell">Phone</TableHead>
              <TableHead>Last Outcome</TableHead>
              <TableHead className="text-center">Attempts</TableHead>
              <TableHead>Flow Status</TableHead>
              <TableHead className="text-right">Last Activity</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {filtered.length === 0 ? (
              <TableRow>
                <TableCell colSpan={7} className="text-center py-8 text-gray-500">
                  No results matching &quot;{search}&quot;
                </TableCell>
              </TableRow>
            ) : (
              filtered.map((p) => (
                <TableRow
                  key={p.project_id}
                  className="cursor-pointer hover:bg-gray-50 transition-colors"
                  onClick={() => onSelectProject(p.project_id)}
                >
                  <TableCell className="font-medium">{p.customer_name}</TableCell>
                  <TableCell>
                    <span className="font-mono text-xs text-gray-600">
                      {p.reference_number}
                    </span>
                  </TableCell>
                  <TableCell className="hidden sm:table-cell text-sm text-gray-600">
                    {p.customer_phone || '--'}
                  </TableCell>
                  <TableCell>
                    {p.latest_outcome ? (
                      <Badge
                        className={`text-xs ${
                          OUTCOME_COLORS[p.latest_outcome] ||
                          'bg-gray-100 text-gray-800'
                        }`}
                      >
                        {OUTCOME_LABELS[p.latest_outcome] || p.latest_outcome}
                      </Badge>
                    ) : (
                      <span className="text-xs text-gray-400">--</span>
                    )}
                  </TableCell>
                  <TableCell className="text-center">
                    <Badge variant="outline" className="font-mono text-xs">
                      {p.attempt_count}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    <Badge
                      className={`text-xs ${
                        FLOW_STATUS_COLORS[p.flow_status] ||
                        'bg-gray-100 text-gray-800'
                      }`}
                    >
                      {p.flow_status}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-right text-sm text-gray-500">
                    {formatRelativeTime(p.last_activity)}
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </div>

      <p className="text-xs text-gray-400 text-right">
        {filtered.length} of {projects.length} project{projects.length !== 1 ? 's' : ''} with voice agent activity
      </p>
    </div>
  )
}
