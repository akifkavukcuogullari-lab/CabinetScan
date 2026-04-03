'use client'

import { useState, useEffect, useCallback, useMemo } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { DateRangeFilter } from '@/components/admin/DateRangeFilter'
import {
  ArrowLeft,
  CheckCircle2,
  Star,
  Clock,
  RotateCw,
  ArrowUpDown,
  Trophy,
  Award,
} from 'lucide-react'
import { calculateDesignerScores, getTierConfig } from '@/lib/designer-scoring'
import {
  BarChart,
  Bar,
  LineChart,
  Line,
  PieChart,
  Pie,
  Cell,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts'
import type { PieLabelRenderProps } from 'recharts'

// ─── Types ───────────────────────────────────────────────────────────────────

interface Designer {
  id: string
  full_name: string
  email: string
  is_active: boolean
}

interface DesignRequest {
  id: string
  designer_id: string | null
  status: string
  accepted_at: string | null
  delivered_at: string | null
  approved_at: string | null
  completed_at: string | null
  estimated_completion_at: string | null
  drop_reason: string | null
  rejection_reason: string | null
  created_at: string
}

interface DesignReview {
  id: string
  design_request_id: string
  designer_id: string
  rating: number
  created_at: string
}

interface ChatMessage {
  design_request_id: string
  sender_type: string
  created_at: string
}

interface DesignFile {
  design_request_id: string
  designer_id: string
}

interface DesignerKPI {
  designerId: string
  name: string
  completed: number
  rejected: number
  dropped: number
  avgCompletionTime: string
  avgCompletionHours: number
  onTimePercent: number
  avgRating: number
  ratingCount: number
  avgResponseTime: string
  avgResponseMs: number
  filesPerProject: number
  active: number
  acceptanceSpeed: string
  acceptanceMs: number
}

type SortKey = keyof DesignerKPI
type SortDir = 'asc' | 'desc'

// ─── Helpers ─────────────────────────────────────────────────────────────────

function formatDuration(ms: number): string {
  if (ms <= 0 || !isFinite(ms)) return '\u2014'
  const hours = ms / (1000 * 60 * 60)
  if (hours < 1) {
    const mins = Math.round(ms / (1000 * 60))
    return `${mins}m`
  }
  if (hours < 24) {
    return `${Math.round(hours)}h`
  }
  const days = Math.floor(hours / 24)
  const remHours = Math.round(hours % 24)
  if (remHours === 0) return `${days}d`
  return `${days}d ${remHours}h`
}

function renderStars(rating: number): React.ReactNode {
  const filled = Math.round(rating)
  return (
    <span className="inline-flex items-center gap-0.5">
      {[1, 2, 3, 4, 5].map((i) => (
        <Star
          key={i}
          className={`h-3.5 w-3.5 ${
            i <= filled ? 'fill-yellow-400 text-yellow-400' : 'text-gray-300'
          }`}
        />
      ))}
      <span className="ml-1 text-sm text-muted-foreground">
        {rating > 0 ? rating.toFixed(1) : '\u2014'}
      </span>
    </span>
  )
}

const PIE_COLORS = [
  '#3B82F6', // blue
  '#10B981', // green
  '#F59E0B', // amber
  '#EF4444', // red
  '#8B5CF6', // violet
  '#EC4899', // pink
  '#06B6D4', // cyan
  '#F97316', // orange
]

const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

// ─── Component ───────────────────────────────────────────────────────────────

export default function DesignerPerformancePage() {
  const router = useRouter()
  const supabase = createClient()

  // Date range: default to current month
  const [startDate, setStartDate] = useState<Date>(() => {
    const now = new Date()
    return new Date(now.getFullYear(), now.getMonth(), 1)
  })
  const [endDate, setEndDate] = useState<Date>(() => {
    const now = new Date()
    now.setHours(23, 59, 59, 999)
    return now
  })

  // Raw data
  const [designers, setDesigners] = useState<Designer[]>([])
  const [requests, setRequests] = useState<DesignRequest[]>([])
  const [reviews, setReviews] = useState<DesignReview[]>([])
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [files, setFiles] = useState<DesignFile[]>([])
  const [loading, setLoading] = useState(true)

  // Sort state
  const [sortKey, setSortKey] = useState<SortKey>('completed')
  const [sortDir, setSortDir] = useState<SortDir>('desc')

  // ── Fetch data ──

  const fetchData = useCallback(async () => {
    setLoading(true)
    const isoStart = startDate.toISOString()
    const isoEnd = endDate.toISOString()

    const [designersRes, requestsRes, reviewsRes, messagesRes, filesRes] = await Promise.all([
      supabase.from('designers').select('id, full_name, email, is_active').eq('is_active', true),
      supabase
        .from('design_requests')
        .select('id, designer_id, status, accepted_at, delivered_at, approved_at, completed_at, estimated_completion_at, drop_reason, rejection_reason, created_at')
        .gte('created_at', isoStart)
        .lte('created_at', isoEnd),
      supabase
        .from('design_reviews')
        .select('id, design_request_id, designer_id, rating, created_at')
        .gte('created_at', isoStart)
        .lte('created_at', isoEnd),
      supabase
        .from('design_chat_messages')
        .select('design_request_id, sender_type, created_at')
        .gte('created_at', isoStart)
        .lte('created_at', isoEnd)
        .order('created_at', { ascending: true }),
      supabase
        .from('design_files')
        .select('design_request_id, designer_id')
        .gte('created_at', isoStart)
        .lte('created_at', isoEnd),
    ])

    setDesigners(designersRes.data ?? [])
    setRequests(requestsRes.data ?? [])
    setReviews(reviewsRes.data ?? [])
    setMessages(messagesRes.data ?? [])
    setFiles(filesRes.data ?? [])
    setLoading(false)
  }, [supabase, startDate, endDate])

  useEffect(() => {
    fetchData()
  }, [fetchData])

  // ── Computed KPIs ──

  const designerKPIs = useMemo((): DesignerKPI[] => {
    return designers.map((designer) => {
      const dRequests = requests.filter((r) => r.designer_id === designer.id)
      const dReviews = reviews.filter((r) => r.designer_id === designer.id)
      const dFiles = files.filter((f) => f.designer_id === designer.id)

      // Completed
      const completed = dRequests.filter(
        (r) => r.status === 'completed' && r.completed_at
      ).length

      // Rejected
      const rejected = dRequests.filter((r) => r.rejection_reason != null).length

      // Dropped
      const dropped = dRequests.filter((r) => r.drop_reason != null).length

      // Avg Completion Time (delivered_at - accepted_at)
      const completionTimes: number[] = []
      for (const r of dRequests) {
        if (r.delivered_at && r.accepted_at) {
          const diff = new Date(r.delivered_at).getTime() - new Date(r.accepted_at).getTime()
          if (diff > 0) completionTimes.push(diff)
        }
      }
      const avgCompletionMs =
        completionTimes.length > 0
          ? completionTimes.reduce((a, b) => a + b, 0) / completionTimes.length
          : 0

      // On-Time %
      const withBothDates = dRequests.filter(
        (r) => r.delivered_at && r.estimated_completion_at
      )
      const onTime = withBothDates.filter(
        (r) =>
          new Date(r.delivered_at!).getTime() <=
          new Date(r.estimated_completion_at!).getTime()
      ).length
      const onTimePercent =
        withBothDates.length > 0 ? (onTime / withBothDates.length) * 100 : -1

      // Avg Rating
      const avgRating =
        dReviews.length > 0
          ? dReviews.reduce((sum, r) => sum + r.rating, 0) / dReviews.length
          : 0

      // Avg Response Time
      const responseTimes: number[] = []
      const requestIds = new Set(dRequests.map((r) => r.id))
      const relevantMessages = messages.filter((m) => requestIds.has(m.design_request_id))
      const grouped = new Map<string, ChatMessage[]>()
      for (const m of relevantMessages) {
        const arr = grouped.get(m.design_request_id) || []
        arr.push(m)
        grouped.set(m.design_request_id, arr)
      }
      for (const [, msgs] of grouped) {
        for (let i = 0; i < msgs.length - 1; i++) {
          if (
            msgs[i].sender_type === 'showroom' &&
            msgs[i + 1].sender_type === 'designer'
          ) {
            const diff =
              new Date(msgs[i + 1].created_at).getTime() -
              new Date(msgs[i].created_at).getTime()
            if (diff > 0) responseTimes.push(diff)
          }
        }
      }
      const avgResponseMs =
        responseTimes.length > 0
          ? responseTimes.reduce((a, b) => a + b, 0) / responseTimes.length
          : 0

      // Files per project
      const completedRequestIds = new Set(
        dRequests.filter((r) => r.status === 'completed').map((r) => r.id)
      )
      const fileCount = dFiles.filter((f) =>
        completedRequestIds.has(f.design_request_id)
      ).length
      const filesPerProject =
        completedRequestIds.size > 0 ? fileCount / completedRequestIds.size : 0

      // Active
      const active = dRequests.filter(
        (r) => !['completed', 'canceled', 'pending'].includes(r.status)
      ).length

      // Acceptance Speed (accepted_at - created_at)
      const acceptanceTimes: number[] = []
      for (const r of dRequests) {
        if (r.accepted_at) {
          const diff =
            new Date(r.accepted_at).getTime() - new Date(r.created_at).getTime()
          if (diff > 0) acceptanceTimes.push(diff)
        }
      }
      const avgAcceptanceMs =
        acceptanceTimes.length > 0
          ? acceptanceTimes.reduce((a, b) => a + b, 0) / acceptanceTimes.length
          : 0

      return {
        designerId: designer.id,
        name: designer.full_name,
        completed,
        rejected,
        dropped,
        avgCompletionTime: formatDuration(avgCompletionMs),
        avgCompletionHours: avgCompletionMs / (1000 * 60 * 60),
        onTimePercent,
        avgRating,
        ratingCount: dReviews.length,
        avgResponseTime: formatDuration(avgResponseMs),
        avgResponseMs,
        filesPerProject,
        active,
        acceptanceSpeed: formatDuration(avgAcceptanceMs),
        acceptanceMs: avgAcceptanceMs,
      }
    })
  }, [designers, requests, reviews, messages, files])

  // ── Summary cards ──

  const summaryStats = useMemo(() => {
    const completedCount = requests.filter(
      (r) => r.status === 'completed' && r.completed_at
    ).length

    const allRatings = reviews.map((r) => r.rating)
    const avgRating =
      allRatings.length > 0
        ? allRatings.reduce((a, b) => a + b, 0) / allRatings.length
        : 0

    const withBothDates = requests.filter(
      (r) => r.delivered_at && r.estimated_completion_at
    )
    const onTime = withBothDates.filter(
      (r) =>
        new Date(r.delivered_at!).getTime() <=
        new Date(r.estimated_completion_at!).getTime()
    ).length
    const onTimeRate =
      withBothDates.length > 0 ? (onTime / withBothDates.length) * 100 : 0

    const completedRequests = requests.filter((r) => r.status === 'completed')
    const revisedCount = completedRequests.filter(
      (r) => r.rejection_reason != null
    ).length
    const revisionRate =
      completedRequests.length > 0
        ? (revisedCount / completedRequests.length) * 100
        : 0

    return { completedCount, avgRating, onTimeRate, revisionRate }
  }, [requests, reviews])

  // ── Chart data ──

  const ratingDistribution = useMemo(() => {
    const counts = [0, 0, 0, 0, 0]
    for (const r of reviews) {
      const idx = Math.min(Math.max(Math.round(r.rating) - 1, 0), 4)
      counts[idx]++
    }
    return counts.map((count, i) => ({ rating: i + 1, count }))
  }, [reviews])

  const monthlyCompletionTrend = useMemo(() => {
    // Last 6 months
    const now = new Date()
    const months: { month: string; avgDays: number }[] = []
    for (let i = 5; i >= 0; i--) {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1)
      const monthEnd = new Date(d.getFullYear(), d.getMonth() + 1, 0, 23, 59, 59, 999)
      const monthRequests = requests.filter((r) => {
        if (!r.delivered_at || !r.accepted_at) return false
        const completedDate = new Date(r.delivered_at)
        return completedDate >= d && completedDate <= monthEnd
      })
      const times = monthRequests.map(
        (r) =>
          (new Date(r.delivered_at!).getTime() - new Date(r.accepted_at!).getTime()) /
          (1000 * 60 * 60 * 24)
      ).filter((t) => t > 0)
      const avg = times.length > 0 ? times.reduce((a, b) => a + b, 0) / times.length : 0
      months.push({
        month: MONTH_NAMES[d.getMonth()],
        avgDays: Math.round(avg * 10) / 10,
      })
    }
    return months
  }, [requests])

  const statusDistribution = useMemo(() => {
    const map = new Map<string, number>()
    for (const r of requests) {
      const s = r.status || 'unknown'
      map.set(s, (map.get(s) || 0) + 1)
    }
    return Array.from(map.entries()).map(([status, count]) => ({
      status: status.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()),
      count,
    }))
  }, [requests])

  // ── Bonus Scores ──

  const bonusScores = useMemo(() => {
    if (!designers.length) return []
    return calculateDesignerScores({
      designers: designers.map((d) => ({ id: d.id, full_name: d.full_name })),
      requests,
      reviews,
    })
  }, [designers, requests, reviews])

  // ── Sorting ──

  const sortedKPIs = useMemo(() => {
    const sorted = [...designerKPIs]
    sorted.sort((a, b) => {
      let aVal: number | string = a[sortKey] as number | string
      let bVal: number | string = b[sortKey] as number | string

      // For formatted duration fields, sort by underlying ms values
      if (sortKey === 'avgCompletionTime') {
        aVal = a.avgCompletionHours
        bVal = b.avgCompletionHours
      } else if (sortKey === 'avgResponseTime') {
        aVal = a.avgResponseMs
        bVal = b.avgResponseMs
      } else if (sortKey === 'acceptanceSpeed') {
        aVal = a.acceptanceMs
        bVal = b.acceptanceMs
      }

      if (typeof aVal === 'string' && typeof bVal === 'string') {
        return sortDir === 'asc' ? aVal.localeCompare(bVal) : bVal.localeCompare(aVal)
      }
      const numA = aVal as number
      const numB = bVal as number
      return sortDir === 'asc' ? numA - numB : numB - numA
    })
    return sorted
  }, [designerKPIs, sortKey, sortDir])

  // Top performer (highest completed, then highest rating)
  const topPerformerId = useMemo(() => {
    if (designerKPIs.length === 0) return null
    const sorted = [...designerKPIs].sort((a, b) => {
      if (b.completed !== a.completed) return b.completed - a.completed
      return b.avgRating - a.avgRating
    })
    return sorted[0]?.completed > 0 ? sorted[0].designerId : null
  }, [designerKPIs])

  const handleSort = (key: SortKey) => {
    if (sortKey === key) {
      setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'))
    } else {
      setSortKey(key)
      setSortDir('desc')
    }
  }

  const handleRangeChange = (start: Date, end: Date) => {
    setStartDate(start)
    setEndDate(end)
  }

  const SortableHeader = ({
    label,
    sortKeyName,
    className,
  }: {
    label: string
    sortKeyName: SortKey
    className?: string
  }) => (
    <TableHead
      className={`cursor-pointer select-none hover:bg-muted/50 ${className ?? ''}`}
      onClick={() => handleSort(sortKeyName)}
    >
      <span className="inline-flex items-center gap-1">
        {label}
        <ArrowUpDown className={`h-3 w-3 ${sortKey === sortKeyName ? 'text-foreground' : 'text-muted-foreground/50'}`} />
      </span>
    </TableHead>
  )

  // ── Render ─────────────────────────────────────────────────────────────────

  if (loading) {
    return (
      <div className="space-y-6">
        <div className="flex items-center gap-3">
          <Link href="/admin/designers">
            <Button variant="ghost" size="icon">
              <ArrowLeft className="h-4 w-4" />
            </Button>
          </Link>
          <div>
            <h1 className="text-2xl font-bold">Designer Performance</h1>
            <p className="text-muted-foreground">Loading performance data...</p>
          </div>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          {[1, 2, 3, 4].map((i) => (
            <Card key={i}>
              <CardContent className="p-6">
                <Skeleton className="h-4 w-24 mb-3" />
                <Skeleton className="h-8 w-16" />
              </CardContent>
            </Card>
          ))}
        </div>
        <Card>
          <CardContent className="p-6 space-y-3">
            {[1, 2, 3, 4, 5].map((i) => (
              <Skeleton key={i} className="h-10 w-full" />
            ))}
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center gap-3">
        <Link href="/admin/designers">
          <Button variant="ghost" size="icon">
            <ArrowLeft className="h-4 w-4" />
          </Button>
        </Link>
        <div>
          <h1 className="text-2xl font-bold">Designer Performance</h1>
          <p className="text-muted-foreground">
            Track designer KPIs and performance metrics
          </p>
        </div>
      </div>

      {/* Date Range Filter */}
      <Card>
        <CardContent className="p-4">
          <DateRangeFilter
            startDate={startDate}
            endDate={endDate}
            onRangeChange={handleRangeChange}
          />
        </CardContent>
      </Card>

      {/* Summary Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <Card>
          <CardContent className="p-6">
            <div className="flex items-center gap-2 text-sm text-muted-foreground mb-2">
              <CheckCircle2 className="h-4 w-4 text-green-500" />
              Total Projects Completed
            </div>
            <p className="text-3xl font-bold">{summaryStats.completedCount}</p>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-6">
            <div className="flex items-center gap-2 text-sm text-muted-foreground mb-2">
              <Star className="h-4 w-4 text-yellow-400" />
              Average Rating
            </div>
            <div className="mt-1">{renderStars(summaryStats.avgRating)}</div>
            <p className="text-xs text-muted-foreground mt-1">
              {reviews.length} review{reviews.length !== 1 ? 's' : ''}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-6">
            <div className="flex items-center gap-2 text-sm text-muted-foreground mb-2">
              <Clock className="h-4 w-4 text-blue-500" />
              On-Time Delivery Rate
            </div>
            <p className="text-3xl font-bold">
              {summaryStats.onTimeRate > 0
                ? `${Math.round(summaryStats.onTimeRate)}%`
                : '\u2014'}
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-6">
            <div className="flex items-center gap-2 text-sm text-muted-foreground mb-2">
              <RotateCw className="h-4 w-4 text-orange-500" />
              Revision Rate
            </div>
            <p className="text-3xl font-bold">
              {summaryStats.revisionRate > 0
                ? `${Math.round(summaryStats.revisionRate)}%`
                : '0%'}
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Per-Designer Performance Table */}
      <Card>
        <CardHeader>
          <CardTitle>Per-Designer Performance</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {sortedKPIs.length === 0 ? (
            <div className="p-8 text-center text-muted-foreground">
              No active designers found.
            </div>
          ) : (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <SortableHeader label="Designer" sortKeyName="name" />
                    <SortableHeader label="Completed" sortKeyName="completed" />
                    <SortableHeader label="Rejected" sortKeyName="rejected" />
                    <SortableHeader label="Dropped" sortKeyName="dropped" />
                    <SortableHeader label="Avg Completion" sortKeyName="avgCompletionTime" />
                    <SortableHeader label="On-Time %" sortKeyName="onTimePercent" />
                    <SortableHeader label="Avg Rating" sortKeyName="avgRating" />
                    <SortableHeader label="Avg Response" sortKeyName="avgResponseTime" />
                    <SortableHeader label="Files/Project" sortKeyName="filesPerProject" />
                    <SortableHeader label="Active" sortKeyName="active" />
                    <SortableHeader label="Accept Speed" sortKeyName="acceptanceSpeed" />
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {sortedKPIs.map((kpi) => {
                    const isTop = kpi.designerId === topPerformerId
                    return (
                      <TableRow
                        key={kpi.designerId}
                        className={`cursor-pointer hover:bg-muted/50 ${
                          isTop ? 'bg-yellow-50/50 dark:bg-yellow-950/20' : ''
                        }`}
                        onClick={() => router.push(`/admin/designers/${kpi.designerId}`)}
                      >
                        <TableCell className="font-medium whitespace-nowrap">
                          <span className="inline-flex items-center gap-2">
                            {kpi.name}
                            {isTop && (
                              <Trophy className="h-4 w-4 text-yellow-500" />
                            )}
                          </span>
                        </TableCell>
                        <TableCell>
                          <Badge
                            variant="outline"
                            className="bg-green-50 text-green-700 border-green-200 dark:bg-green-950 dark:text-green-300 dark:border-green-800"
                          >
                            {kpi.completed}
                          </Badge>
                        </TableCell>
                        <TableCell>
                          {kpi.rejected > 0 ? (
                            <Badge
                              variant="outline"
                              className="bg-red-50 text-red-700 border-red-200 dark:bg-red-950 dark:text-red-300 dark:border-red-800"
                            >
                              {kpi.rejected}
                            </Badge>
                          ) : (
                            <span className="text-muted-foreground">0</span>
                          )}
                        </TableCell>
                        <TableCell>
                          {kpi.dropped > 0 ? (
                            <Badge
                              variant="outline"
                              className="bg-orange-50 text-orange-700 border-orange-200 dark:bg-orange-950 dark:text-orange-300 dark:border-orange-800"
                            >
                              {kpi.dropped}
                            </Badge>
                          ) : (
                            <span className="text-muted-foreground">0</span>
                          )}
                        </TableCell>
                        <TableCell className="whitespace-nowrap">
                          {kpi.avgCompletionTime}
                        </TableCell>
                        <TableCell>
                          {kpi.onTimePercent >= 0 ? (
                            <span
                              className={
                                kpi.onTimePercent >= 80
                                  ? 'text-green-600 font-medium'
                                  : kpi.onTimePercent >= 50
                                  ? 'text-yellow-600 font-medium'
                                  : 'text-red-600 font-medium'
                              }
                            >
                              {Math.round(kpi.onTimePercent)}%
                            </span>
                          ) : (
                            <span className="text-muted-foreground">{'\u2014'}</span>
                          )}
                        </TableCell>
                        <TableCell>{renderStars(kpi.avgRating)}</TableCell>
                        <TableCell className="whitespace-nowrap">
                          {kpi.avgResponseTime}
                        </TableCell>
                        <TableCell>
                          {kpi.filesPerProject > 0
                            ? kpi.filesPerProject.toFixed(1)
                            : '\u2014'}
                        </TableCell>
                        <TableCell>
                          {kpi.active > 0 ? (
                            <Badge
                              variant="outline"
                              className="bg-blue-50 text-blue-700 border-blue-200 dark:bg-blue-950 dark:text-blue-300 dark:border-blue-800"
                            >
                              {kpi.active}
                            </Badge>
                          ) : (
                            <span className="text-muted-foreground">0</span>
                          )}
                        </TableCell>
                        <TableCell className="whitespace-nowrap">
                          {kpi.acceptanceSpeed}
                        </TableCell>
                      </TableRow>
                    )
                  })}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Charts Section */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Rating Distribution */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Rating Distribution</CardTitle>
          </CardHeader>
          <CardContent>
            {reviews.length === 0 ? (
              <div className="h-[250px] flex items-center justify-center text-muted-foreground text-sm">
                No reviews in this period
              </div>
            ) : (
              <ResponsiveContainer width="100%" height={250}>
                <BarChart data={ratingDistribution}>
                  <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
                  <XAxis dataKey="rating" tick={{ fontSize: 12 }} />
                  <YAxis allowDecimals={false} tick={{ fontSize: 12 }} />
                  <Tooltip />
                  <Bar dataKey="count" fill="#3B82F6" radius={[4, 4, 0, 0]} name="Reviews" />
                </BarChart>
              </ResponsiveContainer>
            )}
          </CardContent>
        </Card>

        {/* Monthly Completion Trend */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Avg Completion Time (days)</CardTitle>
          </CardHeader>
          <CardContent>
            {monthlyCompletionTrend.every((m) => m.avgDays === 0) ? (
              <div className="h-[250px] flex items-center justify-center text-muted-foreground text-sm">
                No completion data available
              </div>
            ) : (
              <ResponsiveContainer width="100%" height={250}>
                <LineChart data={monthlyCompletionTrend}>
                  <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
                  <XAxis dataKey="month" tick={{ fontSize: 12 }} />
                  <YAxis tick={{ fontSize: 12 }} />
                  <Tooltip />
                  <Line
                    type="monotone"
                    dataKey="avgDays"
                    stroke="#3B82F6"
                    strokeWidth={2}
                    dot={{ r: 4 }}
                    name="Avg Days"
                  />
                </LineChart>
              </ResponsiveContainer>
            )}
          </CardContent>
        </Card>

        {/* Projects by Status */}
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Projects by Status</CardTitle>
          </CardHeader>
          <CardContent>
            {statusDistribution.length === 0 ? (
              <div className="h-[250px] flex items-center justify-center text-muted-foreground text-sm">
                No projects in this period
              </div>
            ) : (
              <ResponsiveContainer width="100%" height={250}>
                <PieChart>
                  <Pie
                    data={statusDistribution}
                    dataKey="count"
                    nameKey="status"
                    cx="50%"
                    cy="50%"
                    outerRadius={80}
                    label={(props: PieLabelRenderProps) => `${props.name ?? ''}: ${props.value ?? ''}`}
                    labelLine={false}
                  >
                    {statusDistribution.map((_, i) => (
                      <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />
                    ))}
                  </Pie>
                  <Tooltip />
                  <Legend />
                </PieChart>
              </ResponsiveContainer>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Bonus Scores Section */}
      <div className="space-y-4">
        <h2 className="text-lg font-bold flex items-center gap-2">
          <Award className="h-5 w-5" />
          Bonus Scores
        </h2>
        {bonusScores.length === 0 ? (
          <Card>
            <CardContent className="p-8 text-center text-muted-foreground">
              No designers to score.
            </CardContent>
          </Card>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {bonusScores.map((s) => {
              const tierCfg = getTierConfig(s.tier)
              return (
                <Card key={s.designerId} className={`border ${s.isEligible ? tierCfg.bgColor : ''}`}>
                  <CardContent className="p-4 space-y-3">
                    <div className="flex items-center justify-between">
                      <span className="font-semibold">{s.designerName}</span>
                      {s.isEligible ? (
                        <span className="text-lg flex items-center gap-1">
                          {tierCfg.emoji}{' '}
                          <Badge className={tierCfg.bgColor}>{tierCfg.label}</Badge>
                        </span>
                      ) : (
                        <Badge variant="outline">Not Eligible</Badge>
                      )}
                    </div>
                    <div className="text-3xl font-bold text-center">
                      {s.isEligible ? s.totalScore.toFixed(1) : '\u2014'}
                      <span className="text-sm font-normal text-gray-500"> / 100</span>
                    </div>
                    {s.isEligible && (
                      <div className="space-y-1.5">
                        {Object.entries(s.breakdown).map(([key, val]) => (
                          <div key={key} className="flex items-center gap-2 text-xs">
                            <span className="w-20 text-gray-500 capitalize">{key}</span>
                            <div className="flex-1 bg-gray-100 rounded-full h-2">
                              <div
                                className={`h-2 rounded-full ${
                                  val.score / val.max >= 0.8
                                    ? 'bg-green-500'
                                    : val.score / val.max >= 0.5
                                    ? 'bg-yellow-500'
                                    : 'bg-red-500'
                                }`}
                                style={{ width: `${(val.score / val.max) * 100}%` }}
                              />
                            </div>
                            <span className="w-12 text-right">
                              {val.score}/{val.max}
                            </span>
                          </div>
                        ))}
                      </div>
                    )}
                    {!s.isEligible && (
                      <p className="text-xs text-gray-500 text-center">
                        Needs 3+ completed projects ({s.completedCount}/3)
                      </p>
                    )}
                    {s.improvements.length > 0 && s.isEligible && (
                      <p className="text-xs text-blue-600 mt-2">
                        {s.improvements[0]}
                      </p>
                    )}
                  </CardContent>
                </Card>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}
