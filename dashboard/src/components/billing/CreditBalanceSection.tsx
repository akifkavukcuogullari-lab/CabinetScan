'use client'

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card'
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
import { Wallet, Plus, AlertTriangle, Loader2, ArrowDownLeft, ArrowUpRight, Gift } from 'lucide-react'

interface CreditBalance {
  balance_cents: number
  low_balance_threshold_cents: number
}

interface CreditTransaction {
  id: string
  type: string
  amount_cents: number
  balance_after_cents: number
  service_type: string | null
  notes: string | null
  created_at: string
}

const TOPUP_PRESETS = [
  { label: '$20', cents: 2000 },
  { label: '$50', cents: 5000 },
]

export function CreditBalanceSection({ showroomId }: { showroomId: string }) {
  const supabase = createClient()
  const [balance, setBalance] = useState<CreditBalance | null>(null)
  const [transactions, setTransactions] = useState<CreditTransaction[]>([])
  const [loading, setLoading] = useState(true)
  const [topupLoading, setTopupLoading] = useState<number | string | null>(null)
  const [customAmount, setCustomAmount] = useState('')
  const [thresholdInput, setThresholdInput] = useState('')
  const [savingThreshold, setSavingThreshold] = useState(false)

  const loadData = useCallback(async () => {
    const { data: balanceData } = await supabase
      .from('showroom_credit_balances')
      .select('balance_cents, low_balance_threshold_cents')
      .eq('showroom_id', showroomId)
      .single()

    if (balanceData) {
      setBalance(balanceData)
      setThresholdInput(String(balanceData.low_balance_threshold_cents / 100))
    } else {
      setBalance({ balance_cents: 0, low_balance_threshold_cents: 1000 })
      setThresholdInput('10')
    }

    const { data: txnData } = await supabase
      .from('showroom_credit_transactions')
      .select('id, type, amount_cents, balance_after_cents, service_type, notes, created_at')
      .eq('showroom_id', showroomId)
      .order('created_at', { ascending: false })
      .limit(15)

    if (txnData) setTransactions(txnData)
    setLoading(false)
  }, [showroomId, supabase])

  useEffect(() => {
    loadData()
  }, [loadData])

  const handleTopup = async (amountCents: number) => {
    setTopupLoading(amountCents)
    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session?.access_token) return

      const response = await fetch(
        `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/credit-topup`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${session.access_token}`,
            'apikey': process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '',
          },
          body: JSON.stringify({ showroom_id: showroomId, amount_cents: amountCents }),
        }
      )

      const data = await response.json()
      if (data.url) {
        window.location.href = data.url
      }
    } catch (err) {
      console.error('Top-up error:', err)
    } finally {
      setTopupLoading(null)
    }
  }

  const handleSaveThreshold = async () => {
    const cents = Math.round(parseFloat(thresholdInput) * 100)
    if (isNaN(cents) || cents < 0) return

    setSavingThreshold(true)
    await supabase
      .from('showroom_credit_balances')
      .upsert({ showroom_id: showroomId, low_balance_threshold_cents: cents }, { onConflict: 'showroom_id' })

    setBalance((prev) => prev ? { ...prev, low_balance_threshold_cents: cents } : prev)
    setSavingThreshold(false)
  }

  if (loading) {
    return (
      <Card>
        <CardContent className="py-8 flex items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-gray-400" />
        </CardContent>
      </Card>
    )
  }

  const balanceDollars = ((balance?.balance_cents || 0) / 100).toFixed(2)
  const isLow = (balance?.balance_cents || 0) <= (balance?.low_balance_threshold_cents || 1000)

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-blue-100 rounded-lg">
              <Wallet className="h-5 w-5 text-blue-600" />
            </div>
            <div>
              <CardTitle>Credit Balance</CardTitle>
              <CardDescription>For voice agent calls, SMS, and design requests</CardDescription>
            </div>
          </div>
          <div className="text-right">
            <p className={`text-3xl font-bold ${isLow ? 'text-red-600' : 'text-gray-900'}`}>
              ${balanceDollars}
            </p>
            {isLow && (
              <div className="flex items-center gap-1 text-amber-600 text-xs mt-1">
                <AlertTriangle className="h-3 w-3" />
                Low balance
              </div>
            )}
          </div>
        </div>
      </CardHeader>
      <CardContent className="space-y-6">
        {/* Top-up Buttons */}
        <div>
          <p className="text-sm font-medium text-gray-700 mb-2">Add Credits</p>
          <div className="flex gap-2 flex-wrap items-center">
            {TOPUP_PRESETS.map((preset) => (
              <Button
                key={preset.cents}
                variant="outline"
                size="sm"
                onClick={() => handleTopup(preset.cents)}
                disabled={topupLoading !== null}
              >
                {topupLoading === preset.cents ? (
                  <Loader2 className="h-4 w-4 animate-spin mr-1" />
                ) : (
                  <Plus className="h-4 w-4 mr-1" />
                )}
                {preset.label}
              </Button>
            ))}
            <div className="flex items-center gap-1.5">
              <span className="text-sm text-gray-400">or</span>
              <div className="flex items-center gap-1">
                <span className="text-sm text-gray-500">$</span>
                <Input
                  type="number"
                  min="1"
                  step="1"
                  placeholder="25"
                  value={customAmount}
                  onChange={(e) => setCustomAmount(e.target.value)}
                  className="w-20 h-8"
                  disabled={topupLoading !== null}
                />
              </div>
              <Button
                variant="outline"
                size="sm"
                onClick={() => {
                  const cents = Math.round(parseFloat(customAmount) * 100)
                  if (cents >= 100) handleTopup(cents)
                }}
                disabled={topupLoading !== null || !customAmount || parseFloat(customAmount) < 1}
              >
                {topupLoading === 'custom' ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  'Add'
                )}
              </Button>
            </div>
          </div>
        </div>

        {/* Low Balance Threshold */}
        <div>
          <p className="text-sm font-medium text-gray-700 mb-2">Low Balance Alert</p>
          <div className="flex items-center gap-2">
            <span className="text-sm text-gray-500">Notify me when below $</span>
            <Input
              type="number"
              min="0"
              step="1"
              value={thresholdInput}
              onChange={(e) => setThresholdInput(e.target.value)}
              className="w-20 h-8"
            />
            <Button
              variant="outline"
              size="sm"
              onClick={handleSaveThreshold}
              disabled={savingThreshold}
            >
              {savingThreshold ? <Loader2 className="h-3 w-3 animate-spin" /> : 'Save'}
            </Button>
          </div>
        </div>

        {/* Recent Transactions */}
        {transactions.length > 0 && (
          <div>
            <p className="text-sm font-medium text-gray-700 mb-2">Recent Transactions</p>
            <div className="border rounded-lg overflow-hidden">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Date</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead>Details</TableHead>
                    <TableHead className="text-right">Amount</TableHead>
                    <TableHead className="text-right">Balance</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {transactions.map((txn) => {
                    const isCredit = txn.amount_cents > 0
                    return (
                      <TableRow key={txn.id}>
                        <TableCell className="text-xs text-gray-500 whitespace-nowrap">
                          {new Date(txn.created_at).toLocaleDateString()}
                        </TableCell>
                        <TableCell>
                          <Badge
                            variant="outline"
                            className={
                              txn.type === 'top_up'
                                ? 'border-green-200 text-green-700 bg-green-50'
                                : txn.type === 'plan_bonus'
                                  ? 'border-purple-200 text-purple-700 bg-purple-50'
                                  : txn.type === 'deduction'
                                    ? 'border-red-200 text-red-700 bg-red-50'
                                    : 'border-gray-200 text-gray-700'
                            }
                          >
                            {txn.type === 'top_up' && <ArrowDownLeft className="h-3 w-3 mr-1" />}
                            {txn.type === 'deduction' && <ArrowUpRight className="h-3 w-3 mr-1" />}
                            {txn.type === 'plan_bonus' && <Gift className="h-3 w-3 mr-1" />}
                            {txn.type.replace('_', ' ')}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-xs text-gray-500 max-w-[200px] truncate">
                          {txn.notes || txn.service_type?.replace('_', ' ') || '-'}
                        </TableCell>
                        <TableCell className={`text-right text-sm font-medium ${isCredit ? 'text-green-600' : 'text-red-600'}`}>
                          {isCredit ? '+' : ''}${(txn.amount_cents / 100).toFixed(2)}
                        </TableCell>
                        <TableCell className="text-right text-xs text-gray-500">
                          ${(txn.balance_after_cents / 100).toFixed(2)}
                        </TableCell>
                      </TableRow>
                    )
                  })}
                </TableBody>
              </Table>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
