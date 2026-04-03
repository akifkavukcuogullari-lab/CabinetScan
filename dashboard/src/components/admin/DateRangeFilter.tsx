'use client'

import { Button } from '@/components/ui/button'
import { CalendarDays } from 'lucide-react'

interface DateRangeFilterProps {
  startDate: Date
  endDate: Date
  onRangeChange: (start: Date, end: Date) => void
}

type Preset = {
  label: string
  getRange: () => [Date, Date]
}

function startOfMonth(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), 1)
}

function endOfDay(date: Date): Date {
  const d = new Date(date)
  d.setHours(23, 59, 59, 999)
  return d
}

function toInputValue(date: Date): string {
  const y = date.getFullYear()
  const m = String(date.getMonth() + 1).padStart(2, '0')
  const d = String(date.getDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

function formatDisplay(date: Date): string {
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

const presets: Preset[] = [
  {
    label: 'This Month',
    getRange: () => {
      const now = new Date()
      return [startOfMonth(now), endOfDay(now)]
    },
  },
  {
    label: 'Last Month',
    getRange: () => {
      const now = new Date()
      const start = new Date(now.getFullYear(), now.getMonth() - 1, 1)
      const end = new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59, 999)
      return [start, end]
    },
  },
  {
    label: 'Last 3 Months',
    getRange: () => {
      const now = new Date()
      const start = new Date(now.getFullYear(), now.getMonth() - 2, 1)
      return [start, endOfDay(now)]
    },
  },
  {
    label: 'Last 6 Months',
    getRange: () => {
      const now = new Date()
      const start = new Date(now.getFullYear(), now.getMonth() - 5, 1)
      return [start, endOfDay(now)]
    },
  },
  {
    label: 'This Year',
    getRange: () => {
      const now = new Date()
      const start = new Date(now.getFullYear(), 0, 1)
      return [start, endOfDay(now)]
    },
  },
]

export function DateRangeFilter({ startDate, endDate, onRangeChange }: DateRangeFilterProps) {
  const handleStartChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = e.target.value
    if (!val) return
    const newStart = new Date(val + 'T00:00:00')
    if (newStart <= endDate) {
      onRangeChange(newStart, endDate)
    }
  }

  const handleEndChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = e.target.value
    if (!val) return
    const newEnd = new Date(val + 'T23:59:59.999')
    if (newEnd >= startDate) {
      onRangeChange(startDate, newEnd)
    }
  }

  const isPresetActive = (preset: Preset): boolean => {
    const [ps, pe] = preset.getRange()
    return (
      ps.toDateString() === startDate.toDateString() &&
      pe.toDateString() === endDate.toDateString()
    )
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-2 text-sm text-muted-foreground">
        <CalendarDays className="h-4 w-4" />
        <span>
          {formatDisplay(startDate)} &mdash; {formatDisplay(endDate)}
        </span>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        {presets.map((preset) => (
          <Button
            key={preset.label}
            variant={isPresetActive(preset) ? 'default' : 'outline'}
            size="sm"
            onClick={() => {
              const [s, e] = preset.getRange()
              onRangeChange(s, e)
            }}
          >
            {preset.label}
          </Button>
        ))}

        <div className="flex items-center gap-2 ml-2">
          <input
            type="date"
            value={toInputValue(startDate)}
            onChange={handleStartChange}
            className="h-9 rounded-md border border-input bg-background px-3 py-1 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          />
          <span className="text-muted-foreground text-sm">to</span>
          <input
            type="date"
            value={toInputValue(endDate)}
            onChange={handleEndChange}
            className="h-9 rounded-md border border-input bg-background px-3 py-1 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
          />
        </div>
      </div>
    </div>
  )
}
