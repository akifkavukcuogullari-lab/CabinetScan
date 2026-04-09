export interface ScoreBreakdown {
  quality: { score: number; max: 30; avgRating: number }
  speed: { score: number; max: 25; avgCompletionHours: number }
  reliability: { score: number; max: 20; onTimeRate: number }
  productivity: { score: number; max: 15; completedCount: number }
  consistency: { score: number; max: 5; revisionRate: number }
  commitment: { score: number; max: 5; dropRate: number }
}

export interface DesignerScore {
  designerId: string
  designerName: string
  totalScore: number
  tier: 'gold' | 'silver' | 'bronze' | 'none'
  isEligible: boolean
  completedCount: number
  breakdown: ScoreBreakdown
  improvements: string[]
}

interface RequestData {
  designer_id: string | null
  status: string
  accepted_at: string | null
  delivered_at: string | null
  estimated_completion_at: string | null
  drop_reason: string | null
  rejection_reason: string | null
}

interface ReviewData {
  designer_id?: string
  rating: number
}

function getTier(score: number): 'gold' | 'silver' | 'bronze' | 'none' {
  if (score >= 90) return 'gold'
  if (score >= 70) return 'silver'
  if (score >= 50) return 'bronze'
  return 'none'
}

export function getTierConfig(tier: string): { label: string; color: string; bgColor: string; emoji: string } {
  switch (tier) {
    case 'gold': return { label: 'Gold', color: 'text-yellow-700', bgColor: 'bg-yellow-50 border-yellow-200', emoji: '🥇' }
    case 'silver': return { label: 'Silver', color: 'text-gray-600', bgColor: 'bg-gray-100 border-gray-300', emoji: '🥈' }
    case 'bronze': return { label: 'Bronze', color: 'text-orange-700', bgColor: 'bg-orange-50 border-orange-200', emoji: '🥉' }
    default: return { label: 'No Tier', color: 'text-gray-400', bgColor: 'bg-gray-50 border-gray-100', emoji: '' }
  }
}

function getCompletionHours(req: RequestData): number | null {
  if (!req.accepted_at || !req.delivered_at) return null
  return (new Date(req.delivered_at).getTime() - new Date(req.accepted_at).getTime()) / (1000 * 60 * 60)
}

function generateImprovements(breakdown: ScoreBreakdown): string[] {
  const tips: string[] = []
  const { quality, speed, reliability, consistency, commitment } = breakdown

  if (quality.score < 24 && quality.avgRating > 0) {
    const potential = Math.round((4.5 / 5) * 30 - quality.score)
    if (potential > 0) tips.push(`Your average rating is ${quality.avgRating.toFixed(1)}. Improving to 4.5+ would earn you ${potential} more quality points.`)
  }
  if (speed.score < 20 && speed.avgCompletionHours > 0) {
    const days = (speed.avgCompletionHours / 24).toFixed(1)
    tips.push(`Your average delivery time is ${days} days. Delivering under 24 hours would maximize your speed score.`)
  }
  if (reliability.score < 16 && reliability.onTimeRate < 0.9) {
    const currentPct = Math.round(reliability.onTimeRate * 100)
    const potential = Math.round(0.9 * 20 - reliability.score)
    if (potential > 0) tips.push(`You delivered ${currentPct}% of projects on time. Hitting 90%+ would add ${potential} reliability points.`)
  }
  if (consistency.score < 4 && consistency.revisionRate > 0.2) {
    const pct = Math.round(consistency.revisionRate * 100)
    const potential = Math.round((1 - 0.1) * 5 - consistency.score)
    if (potential > 0) tips.push(`${pct}% of your projects needed revision. Cleaner first deliveries would add ${potential} points.`)
  }
  if (commitment.score < 5 && commitment.dropRate > 0) {
    const potential = Math.round(5 - commitment.score)
    if (potential > 0) tips.push(`You dropped some projects. Completing all accepted work would add ${potential} commitment points.`)
  }
  if (tips.length === 0 && breakdown.quality.avgRating > 0) {
    tips.push('Great performance! Keep up the excellent work.')
  }
  return tips
}

function computeScoreForDesigner(
  designerRequests: RequestData[],
  designerReviews: ReviewData[],
  fastestHours: number | null,
  topCompletedCount: number,
  speedBenchmark?: number // if set, use fixed benchmark instead of relative
): ScoreBreakdown {
  const completed = designerRequests.filter(r => r.status === 'completed' || r.status === 'approved')
  const completedCount = completed.length

  // Quality
  const avgRating = designerReviews.length > 0
    ? designerReviews.reduce((sum, r) => sum + r.rating, 0) / designerReviews.length
    : 0
  const qualityScore = avgRating > 0 ? Math.round((avgRating / 5) * 30 * 10) / 10 : 0

  // Speed
  const completionHours = designerRequests
    .filter(r => (r.status === 'completed' || r.status === 'approved' || r.status === 'delivered'))
    .map(getCompletionHours)
    .filter((h): h is number => h !== null && h > 0)
  const avgCompletionHours = completionHours.length > 0
    ? completionHours.reduce((a, b) => a + b, 0) / completionHours.length
    : 0

  let speedScore = 0
  if (avgCompletionHours > 0) {
    if (speedBenchmark) {
      speedScore = Math.min(25, Math.round((speedBenchmark / avgCompletionHours) * 25 * 10) / 10)
    } else if (fastestHours && fastestHours > 0) {
      speedScore = Math.min(25, Math.round((fastestHours / avgCompletionHours) * 25 * 10) / 10)
    }
  }

  // Reliability
  const withEstimate = designerRequests.filter(r => r.delivered_at && r.estimated_completion_at)
  const onTime = withEstimate.filter(r => new Date(r.delivered_at!) <= new Date(r.estimated_completion_at!))
  const onTimeRate = withEstimate.length > 0 ? onTime.length / withEstimate.length : 0
  const reliabilityScore = Math.round(onTimeRate * 20 * 10) / 10

  // Productivity
  let productivityScore = 0
  if (speedBenchmark) {
    productivityScore = Math.min(15, Math.round((completedCount / 10) * 15 * 10) / 10)
  } else if (topCompletedCount > 0) {
    productivityScore = Math.min(15, Math.round((completedCount / topCompletedCount) * 15 * 10) / 10)
  }

  // Consistency (inverse revision rate)
  const revisioned = designerRequests.filter(r => r.rejection_reason)
  const totalAssigned = designerRequests.filter(r => r.designer_id).length
  const revisionRate = totalAssigned > 0 ? revisioned.length / totalAssigned : 0
  const consistencyScore = Math.round((1 - revisionRate) * 5 * 10) / 10

  // Commitment (inverse drop rate)
  const dropped = designerRequests.filter(r => r.drop_reason)
  const dropRate = totalAssigned > 0 ? dropped.length / totalAssigned : 0
  const commitmentScore = Math.round((1 - dropRate) * 5 * 10) / 10

  return {
    quality: { score: qualityScore, max: 30, avgRating },
    speed: { score: speedScore, max: 25, avgCompletionHours },
    reliability: { score: reliabilityScore, max: 20, onTimeRate },
    productivity: { score: productivityScore, max: 15, completedCount },
    consistency: { score: consistencyScore, max: 5, revisionRate },
    commitment: { score: commitmentScore, max: 5, dropRate },
  }
}

// Admin view: relative benchmarks across all designers
export function calculateDesignerScores(params: {
  designers: Array<{ id: string; full_name: string }>
  requests: RequestData[]
  reviews: Array<{ designer_id: string; rating: number }>
}): DesignerScore[] {
  const { designers, requests, reviews } = params

  // Find global benchmarks
  const designerCompletionHours: Record<string, number[]> = {}
  const designerCompletedCounts: Record<string, number> = {}

  for (const req of requests) {
    if (!req.designer_id) continue
    const hours = getCompletionHours(req)
    if (hours && hours > 0 && (req.status === 'completed' || req.status === 'approved' || req.status === 'delivered')) {
      if (!designerCompletionHours[req.designer_id]) designerCompletionHours[req.designer_id] = []
      designerCompletionHours[req.designer_id].push(hours)
    }
    if (req.status === 'completed' || req.status === 'approved') {
      designerCompletedCounts[req.designer_id] = (designerCompletedCounts[req.designer_id] || 0) + 1
    }
  }

  // Fastest avg completion across all designers
  let fastestAvgHours: number | null = null
  for (const hours of Object.values(designerCompletionHours)) {
    const avg = hours.reduce((a, b) => a + b, 0) / hours.length
    if (fastestAvgHours === null || avg < fastestAvgHours) fastestAvgHours = avg
  }

  const topCompletedCount = Math.max(1, ...Object.values(designerCompletedCounts))

  return designers.map(designer => {
    const myRequests = requests.filter(r => r.designer_id === designer.id)
    const myReviews = reviews.filter(r => r.designer_id === designer.id)
    const completedCount = myRequests.filter(r => r.status === 'completed' || r.status === 'approved').length
    const isEligible = completedCount >= 3

    const breakdown = computeScoreForDesigner(myRequests, myReviews, fastestAvgHours, topCompletedCount)
    const totalScore = isEligible
      ? Math.round((breakdown.quality.score + breakdown.speed.score + breakdown.reliability.score + breakdown.productivity.score + breakdown.consistency.score + breakdown.commitment.score) * 10) / 10
      : 0
    const improvements = isEligible ? generateImprovements(breakdown) : ['Complete at least 3 projects to qualify for bonus scoring.']

    return {
      designerId: designer.id,
      designerName: designer.full_name,
      totalScore,
      tier: isEligible ? getTier(totalScore) : 'none',
      isEligible,
      completedCount,
      breakdown,
      improvements,
    }
  })
}

// Designer self-view: fixed benchmarks (no other designer data exposed)
export function calculateSelfScore(params: {
  designerId: string
  designerName: string
  requests: RequestData[]
  reviews: Array<{ rating: number }>
}): DesignerScore {
  const { designerId, designerName, requests, reviews } = params
  const completedCount = requests.filter(r => r.status === 'completed' || r.status === 'approved').length
  const isEligible = completedCount >= 3

  const breakdown = computeScoreForDesigner(
    requests,
    reviews,
    null, // not used when speedBenchmark is set
    1,    // not used when speedBenchmark is set
    24    // 24 hours = max speed points
  )

  const totalScore = isEligible
    ? Math.round((breakdown.quality.score + breakdown.speed.score + breakdown.reliability.score + breakdown.productivity.score + breakdown.consistency.score + breakdown.commitment.score) * 10) / 10
    : 0
  const improvements = isEligible ? generateImprovements(breakdown) : ['Complete at least 3 projects to qualify for bonus scoring.']

  return {
    designerId,
    designerName,
    totalScore,
    tier: isEligible ? getTier(totalScore) : 'none',
    isEligible,
    completedCount,
    breakdown,
    improvements,
  }
}
