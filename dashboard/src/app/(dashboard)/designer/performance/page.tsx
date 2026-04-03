'use client'

import { useState, useEffect, useMemo, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Skeleton } from '@/components/ui/skeleton'
import { DateRangeFilter } from '@/components/admin/DateRangeFilter'
import { calculateSelfScore, getTierConfig } from '@/lib/designer-scoring'
import type { DesignerScore } from '@/lib/designer-scoring'
import {
  CheckCircle2,
  Star,
  Clock,
  TrendingUp,
  Lightbulb,
  Target,
} from 'lucide-react'
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from 'recharts'

const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

const BREAKDOWN_LABELS: Record<string, string> = {
  quality: 'Quality',
  speed: 'Speed',
  reliability: 'Reliability',
  productivity: 'Productivity',
  consistency: 'Consistency',
  commitment: 'Commitment',
}

interface RequestRow {
  id: string
  designer_id: string | null
  status: string
  accepted_at: string | null
  delivered_at: string | null
  estimated_completion_at: string | null
  drop_reason: string | null
  rejection_reason: string | null
  created_at: string
}

interface ReviewRow {
  rating: number
  created_at: string
}

function formatHours(hours: number): string {
  if (hours <= 0 || !isFinite(hours)) return '\u2014'
  if (hours < 1) return `${Math.round(hours * 60)}m`
  if (hours < 24) return `${Math.round(hours)}h`
  const days = Math.floor(hours / 24)
  const rem = Math.round(hours % 24)
  if (rem === 0) return `${days}d`
  return `${days}d ${rem}h`
}

function renderStars(rating: number): React.ReactNode {
  const filled = Math.round(rating)
  return (
    <span className="inline-flex items-center gap-0.5">
      {[1, 2, 3, 4, 5].map((i) => (
        <Star
          key={i}
          className={`h-4 w-4 ${
            i <= filled ? 'fill-yellow-400 text-yellow-400' : 'text-gray-300'
          }`}
        />
      ))}
    </span>
  )
}

export default function DesignerPerformancePage() {
  const supabase = createClient()

  const [startDate, setStartDate] = useState<Date>(() => {
    const now = new Date()
    return new Date(now.getFullYear(), now.getMonth(), 1)
  })
  const [endDate, setEndDate] = useState<Date>(() => {
    const now = new Date()
    now.setHours(23, 59, 59, 999)
    return now
  })

  const [score, setScore] = useState<DesignerScore | null>(null)
  const [requests, setRequests] = useState<RequestRow[]>([])
  const [reviews, setReviews] = useState<ReviewRow[]>([])
  const [loading, setLoading] = useState(true)
  const [designerInfo, setDesignerInfo] = useState<{ id: string; full_name: string } | null>(null)

  const fetchData = useCallback(async () => {
    setLoading(true)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return

      const { data: designer } = await supabase
        .from('designers')
        .select('id, full_name')
        .eq('user_id', user.id)
        .single()
      if (!designer) return

      setDesignerInfo(designer)

      const isoStart = startDate.toISOString()
      const isoEnd = endDate.toISOString()

      const [reqRes, revRes] = await Promise.all([
        supabase
          .from('design_requests')
          .select('id, designer_id, status, accepted_at, delivered_at, estimated_completion_at, drop_reason, rejection_reason, created_at')
          .eq('designer_id', designer.id)
          .gte('created_at', isoStart)
          .lte('created_at', isoEnd),
        supabase
          .from('design_reviews')
          .select('rating, created_at')
          .eq('designer_id', designer.id)
          .gte('created_at', isoStart)
          .lte('created_at', isoEnd),
      ])

      const reqs = reqRes.data ?? []
      const revs = revRes.data ?? []
      setRequests(reqs)
      setReviews(revs)

      const result = calculateSelfScore({
        designerId: designer.id,
        designerName: designer.full_name,
        requests: reqs,
        reviews: revs,
      })
      setScore(result)
    } finally {
      setLoading(false)
    }
  }, [supabase, startDate, endDate])

  useEffect(() => {
    fetchData()
  }, [fetchData])

  // Monthly trend: calculate score per month for last 6 months
  const monthlyTrend = useMemo(() => {
    if (!designerInfo || requests.length === 0) return []
    const now = new Date()
    const months: { month: string; score: number }[] = []

    for (let i = 5; i >= 0; i--) {
      const monthStart = new Date(now.getFullYear(), now.getMonth() - i, 1)
      const monthEnd = new Date(monthStart.getFullYear(), monthStart.getMonth() + 1, 0, 23, 59, 59, 999)

      const monthRequests = requests.filter((r) => {
        const d = new Date(r.created_at)
        return d >= monthStart && d <= monthEnd
      })
      const monthReviews = reviews.filter((r) => {
        const d = new Date(r.created_at)
        return d >= monthStart && d <= monthEnd
      })

      if (monthRequests.length === 0) {
        months.push({ month: MONTH_NAMES[monthStart.getMonth()], score: 0 })
        continue
      }

      const monthScore = calculateSelfScore({
        designerId: designerInfo.id,
        designerName: designerInfo.full_name,
        requests: monthRequests,
        reviews: monthReviews,
      })

      months.push({
        month: MONTH_NAMES[monthStart.getMonth()],
        score: monthScore.isEligible ? monthScore.totalScore : 0,
      })
    }
    return months
  }, [designerInfo, requests, reviews])

  // Stats
  const stats = useMemo(() => {
    if (!score) return null
    const { breakdown } = score
    return {
      completedCount: breakdown.productivity.completedCount,
      avgRating: breakdown.quality.avgRating,
      avgDeliveryHours: breakdown.speed.avgCompletionHours,
      onTimeRate: breakdown.reliability.onTimeRate,
    }
  }, [score])

  const handleRangeChange = (start: Date, end: Date) => {
    setStartDate(start)
    setEndDate(end)
  }

  if (loading) {
    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold">My Performance</h1>
          <p className="text-muted-foreground">Loading your performance data...</p>
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
      </div>
    )
  }

  if (!score) {
    return (
      <div className="space-y-6">
        <div>
          <h1 className="text-2xl font-bold">My Performance</h1>
          <p className="text-muted-foreground">Could not load performance data.</p>
        </div>
      </div>
    )
  }

  const tierConfig = getTierConfig(score.tier)

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold">My Performance</h1>
        <p className="text-muted-foreground">
          Track your score, tier, and improvement areas
        </p>
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

      {/* Score Card */}
      <Card>
        <CardContent className="p-8 flex flex-col items-center space-y-4">
          <div className="relative">
            <div
              className={`w-32 h-32 rounded-full border-4 flex items-center justify-center ${
                score.isEligible
                  ? score.tier === 'gold'
                    ? 'border-yellow-400 bg-yellow-50'
                    : score.tier === 'silver'
                    ? 'border-gray-400 bg-gray-50'
                    : score.tier === 'bronze'
                    ? 'border-orange-400 bg-orange-50'
                    : 'border-gray-200 bg-gray-50'
                  : 'border-gray-200 bg-gray-50'
              }`}
            >
              <span className="text-4xl font-bold">
                {score.isEligible ? score.totalScore.toFixed(1) : '\u2014'}
              </span>
            </div>
          </div>
          <div className="text-sm text-muted-foreground">out of 100</div>
          {score.isEligible ? (
            <Badge className={`text-base px-4 py-1 ${tierConfig.bgColor} ${tierConfig.color} border`}>
              {tierConfig.emoji} {tierConfig.label}
            </Badge>
          ) : (
            <div className="text-center space-y-1">
              <Badge variant="outline" className="text-sm">Not Eligible</Badge>
              <p className="text-sm text-muted-foreground">
                Complete 3+ projects to qualify ({score.completedCount}/3)
              </p>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Score Breakdown */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            <Target className="h-4 w-4" />
            Score Breakdown
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {Object.entries(score.breakdown).map(([key, val]) => {
            const percentage = val.max > 0 ? val.score / val.max : 0
            const barColor =
              percentage >= 0.8
                ? 'bg-green-500'
                : percentage >= 0.5
                ? 'bg-yellow-500'
                : 'bg-red-500'
            return (
              <div key={key} className="space-y-1">
                <div className="flex items-center justify-between text-sm">
                  <span className="font-medium">{BREAKDOWN_LABELS[key] || key}</span>
                  <span className="text-muted-foreground">
                    {val.score.toFixed(1)} / {val.max}
                  </span>
                </div>
                <div className="w-full bg-gray-100 dark:bg-gray-800 rounded-full h-3">
                  <div
                    className={`h-3 rounded-full transition-all duration-500 ${barColor}`}
                    style={{ width: `${Math.min(percentage * 100, 100)}%` }}
                  />
                </div>
              </div>
            )
          })}
        </CardContent>
      </Card>

      {/* Improvement Tips */}
      {score.improvements.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <Lightbulb className="h-4 w-4 text-yellow-500" />
              Improvement Tips
            </CardTitle>
          </CardHeader>
          <CardContent>
            <ul className="space-y-2">
              {score.improvements.map((tip, i) => (
                <li key={i} className="flex items-start gap-2 text-sm text-muted-foreground">
                  <span className="mt-0.5 shrink-0 text-blue-500">&#x2022;</span>
                  <span>{tip}</span>
                </li>
              ))}
            </ul>
          </CardContent>
        </Card>
      )}

      {/* Monthly Trend */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            <TrendingUp className="h-4 w-4" />
            Monthly Score Trend
          </CardTitle>
        </CardHeader>
        <CardContent>
          {monthlyTrend.every((m) => m.score === 0) ? (
            <div className="h-[250px] flex items-center justify-center text-muted-foreground text-sm">
              Not enough data to show trend
            </div>
          ) : (
            <ResponsiveContainer width="100%" height={250}>
              <LineChart data={monthlyTrend}>
                <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
                <XAxis dataKey="month" tick={{ fontSize: 12 }} />
                <YAxis domain={[0, 100]} tick={{ fontSize: 12 }} />
                <Tooltip />
                <Line
                  type="monotone"
                  dataKey="score"
                  stroke="#3B82F6"
                  strokeWidth={2}
                  dot={{ r: 4 }}
                  name="Score"
                  connectNulls
                />
              </LineChart>
            </ResponsiveContainer>
          )}
        </CardContent>
      </Card>

      {/* Stats Summary */}
      {stats && (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <Card>
            <CardContent className="p-6">
              <div className="flex items-center gap-2 text-sm text-muted-foreground mb-2">
                <CheckCircle2 className="h-4 w-4 text-green-500" />
                Completed Projects
              </div>
              <p className="text-3xl font-bold">{stats.completedCount}</p>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-6">
              <div className="flex items-center gap-2 text-sm text-muted-foreground mb-2">
                <Star className="h-4 w-4 text-yellow-400" />
                Avg Rating
              </div>
              <div className="mt-1">{renderStars(stats.avgRating)}</div>
              <p className="text-sm font-medium mt-1">
                {stats.avgRating > 0 ? stats.avgRating.toFixed(1) : '\u2014'}
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-6">
              <div className="flex items-center gap-2 text-sm text-muted-foreground mb-2">
                <Clock className="h-4 w-4 text-blue-500" />
                Avg Delivery Time
              </div>
              <p className="text-3xl font-bold">
                {formatHours(stats.avgDeliveryHours)}
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-6">
              <div className="flex items-center gap-2 text-sm text-muted-foreground mb-2">
                <TrendingUp className="h-4 w-4 text-purple-500" />
                On-Time Rate
              </div>
              <p className="text-3xl font-bold">
                {stats.onTimeRate > 0
                  ? `${Math.round(stats.onTimeRate * 100)}%`
                  : '\u2014'}
              </p>
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  )
}
