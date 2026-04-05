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
import { Loader2, Search, Phone as PhoneIcon } from 'lucide-react'
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

  const filtered = useMemo(() => {
    if (!search.trim()) return projects
    const q = search.toLowerCase()
    return projects.filter(
      (p) =>
        p.customer_name.toLowerCase().includes(q) ||
        p.reference_number.toLowerCase().includes(q)
    )
  }, [projects, search])

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
