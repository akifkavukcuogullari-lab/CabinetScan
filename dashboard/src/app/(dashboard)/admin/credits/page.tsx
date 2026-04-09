'use client'

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import { Badge } from '@/components/ui/badge'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Loader2, Save, Plus, DollarSign, TrendingUp, Wallet } from 'lucide-react'
import { toast } from 'sonner'

interface ServiceConfig {
  id: string
  service_type: string
  cost_per_unit_cents: number
  unit_description: string
  multiplier: number
  minimum_charge_cents: number
}

interface PlanBonus {
  id: string
  subscription_plan: string
  bonus_cents: number
  frequency: string
  is_active: boolean
}

interface ShowroomBalance {
  showroom_id: string
  balance_cents: number
  showroom_name: string
  total_spent: number
  last_topup: string | null
}

interface Transaction {
  id: string
  showroom_id: string
  type: string
  amount_cents: number
  balance_after_cents: number
  service_type: string | null
  notes: string | null
  created_at: string
  showroom_name?: string
}

export default function AdminCreditsPage() {
  const supabase = createClient()
  const [loading, setLoading] = useState(true)
  const [configs, setConfigs] = useState<ServiceConfig[]>([])
  const [bonuses, setBonuses] = useState<PlanBonus[]>([])
  const [balances, setBalances] = useState<ShowroomBalance[]>([])
  const [transactions, setTransactions] = useState<Transaction[]>([])
  const [savingConfig, setSavingConfig] = useState(false)
  const [savingBonus, setSavingBonus] = useState(false)

  // Add credits modal
  const [addCreditsOpen, setAddCreditsOpen] = useState(false)
  const [addCreditsShowroom, setAddCreditsShowroom] = useState<string | null>(null)
  const [addCreditsAmount, setAddCreditsAmount] = useState('')
  const [addCreditsType, setAddCreditsType] = useState('adjustment')
  const [addCreditsNotes, setAddCreditsNotes] = useState('')
  const [addCreditsLoading, setAddCreditsLoading] = useState(false)

  // Revenue stats
  const [totalBilled, setTotalBilled] = useState(0)
  const [totalActual, setTotalActual] = useState(0)

  const loadData = useCallback(async () => {
    const [configRes, bonusRes, balanceRes, txnRes] = await Promise.all([
      supabase.from('credit_service_config').select('*').order('service_type'),
      supabase.from('credit_plan_bonuses').select('*').order('subscription_plan'),
      supabase.from('showroom_credit_balances').select('showroom_id, balance_cents'),
      supabase
        .from('showroom_credit_transactions')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(50),
    ])

    if (configRes.data) setConfigs(configRes.data)
    if (bonusRes.data) setBonuses(bonusRes.data)

    // Enrich balances with showroom names
    if (balanceRes.data) {
      const showroomIds = balanceRes.data.map((b: any) => b.showroom_id)
      const { data: showrooms } = await supabase
        .from('showrooms')
        .select('id, name')
        .in('id', showroomIds)

      const showroomMap = new Map((showrooms || []).map((s: any) => [s.id, s.name]))

      const enriched = balanceRes.data.map((b: any) => ({
        ...b,
        showroom_name: showroomMap.get(b.showroom_id) || 'Unknown',
        total_spent: 0,
        last_topup: null,
      }))
      setBalances(enriched)
    }

    // Process transactions
    if (txnRes.data) {
      // Get showroom names for transactions
      const txnShowroomIds = [...new Set(txnRes.data.map((t: any) => t.showroom_id))]
      const { data: txnShowrooms } = await supabase
        .from('showrooms')
        .select('id, name')
        .in('id', txnShowroomIds)

      const txnShowroomMap = new Map((txnShowrooms || []).map((s: any) => [s.id, s.name]))

      setTransactions(
        txnRes.data.map((t: any) => ({
          ...t,
          showroom_name: txnShowroomMap.get(t.showroom_id) || 'Unknown',
        }))
      )

      // Calculate revenue (deductions only)
      const deductions = txnRes.data.filter((t: any) => t.type === 'deduction')
      setTotalBilled(deductions.reduce((sum: number, t: any) => sum + Math.abs(t.billed_cost_cents || 0), 0))
      setTotalActual(deductions.reduce((sum: number, t: any) => sum + Math.abs(t.actual_cost_cents || 0), 0))
    }

    setLoading(false)
  }, [supabase])

  useEffect(() => {
    loadData()
  }, [loadData])

  const saveConfig = async (config: ServiceConfig) => {
    setSavingConfig(true)
    const { error } = await supabase
      .from('credit_service_config')
      .update({
        cost_per_unit_cents: config.cost_per_unit_cents,
        multiplier: config.multiplier,
        minimum_charge_cents: config.minimum_charge_cents,
      })
      .eq('id', config.id)

    if (error) {
      toast.error('Failed to save config')
    } else {
      toast.success(`${config.service_type} config saved`)
    }
    setSavingConfig(false)
  }

  const saveBonus = async (bonus: PlanBonus) => {
    setSavingBonus(true)
    const { error } = await supabase
      .from('credit_plan_bonuses')
      .update({
        bonus_cents: bonus.bonus_cents,
        frequency: bonus.frequency,
        is_active: bonus.is_active,
      })
      .eq('id', bonus.id)

    if (error) {
      toast.error('Failed to save bonus')
    } else {
      toast.success(`${bonus.subscription_plan} bonus saved`)
    }
    setSavingBonus(false)
  }

  const handleAddCredits = async () => {
    if (!addCreditsShowroom || !addCreditsAmount) return
    setAddCreditsLoading(true)

    try {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session?.access_token) return

      const response = await fetch(
        `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/credit-admin`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${session.access_token}`,
            'apikey': process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '',
          },
          body: JSON.stringify({
            showroom_id: addCreditsShowroom,
            amount_cents: Math.round(parseFloat(addCreditsAmount) * 100),
            type: addCreditsType,
            notes: addCreditsNotes || null,
          }),
        }
      )

      const data = await response.json()
      if (data.success) {
        toast.success(`Credits added. New balance: $${((data.new_balance_cents || 0) / 100).toFixed(2)}`)
        setAddCreditsOpen(false)
        setAddCreditsAmount('')
        setAddCreditsNotes('')
        loadData()
      } else {
        toast.error(data.error || 'Failed to add credits')
      }
    } catch (err) {
      toast.error('Failed to add credits')
    } finally {
      setAddCreditsLoading(false)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
      </div>
    )
  }

  const profit = totalBilled - totalActual

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Credit Management</h1>
        <p className="text-gray-500">Configure pricing, manage showroom balances, and view revenue</p>
      </div>

      {/* Revenue Summary */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-blue-100 rounded-lg">
                <DollarSign className="h-5 w-5 text-blue-600" />
              </div>
              <div>
                <p className="text-sm text-gray-500">Total Billed</p>
                <p className="text-2xl font-bold">${(totalBilled / 100).toFixed(2)}</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-gray-100 rounded-lg">
                <Wallet className="h-5 w-5 text-gray-600" />
              </div>
              <div>
                <p className="text-sm text-gray-500">Actual Cost</p>
                <p className="text-2xl font-bold">${(totalActual / 100).toFixed(2)}</p>
              </div>
            </div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="pt-6">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-green-100 rounded-lg">
                <TrendingUp className="h-5 w-5 text-green-600" />
              </div>
              <div>
                <p className="text-sm text-gray-500">Profit</p>
                <p className="text-2xl font-bold text-green-600">${(profit / 100).toFixed(2)}</p>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Service Cost Config */}
      <Card>
        <CardHeader>
          <CardTitle>Service Cost Configuration</CardTitle>
          <CardDescription>Set the actual cost, markup multiplier, and minimum charge per service</CardDescription>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Service</TableHead>
                <TableHead>Cost per Unit (cents)</TableHead>
                <TableHead>Unit</TableHead>
                <TableHead>Multiplier</TableHead>
                <TableHead>Min Charge (cents)</TableHead>
                <TableHead>Showroom Pays</TableHead>
                <TableHead></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {configs.map((config, idx) => (
                <TableRow key={config.id}>
                  <TableCell className="font-medium">{config.service_type.replace('_', ' ')}</TableCell>
                  <TableCell>
                    <Input
                      type="number"
                      className="w-20 h-8"
                      value={config.cost_per_unit_cents}
                      onChange={(e) => {
                        const updated = [...configs]
                        updated[idx] = { ...config, cost_per_unit_cents: parseInt(e.target.value) || 0 }
                        setConfigs(updated)
                      }}
                    />
                  </TableCell>
                  <TableCell className="text-sm text-gray-500">{config.unit_description}</TableCell>
                  <TableCell>
                    <Input
                      type="number"
                      step="0.1"
                      className="w-20 h-8"
                      value={config.multiplier}
                      onChange={(e) => {
                        const updated = [...configs]
                        updated[idx] = { ...config, multiplier: parseFloat(e.target.value) || 1 }
                        setConfigs(updated)
                      }}
                    />
                  </TableCell>
                  <TableCell>
                    <Input
                      type="number"
                      className="w-20 h-8"
                      value={config.minimum_charge_cents}
                      onChange={(e) => {
                        const updated = [...configs]
                        updated[idx] = { ...config, minimum_charge_cents: parseInt(e.target.value) || 0 }
                        setConfigs(updated)
                      }}
                    />
                  </TableCell>
                  <TableCell className="text-sm font-medium">
                    ${(Math.max(config.cost_per_unit_cents * config.multiplier, config.minimum_charge_cents) / 100).toFixed(2)}/{config.unit_description.replace('per ', '')}
                  </TableCell>
                  <TableCell>
                    <Button size="sm" variant="outline" onClick={() => saveConfig(config)} disabled={savingConfig}>
                      <Save className="h-3 w-3" />
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Plan Bonuses */}
      <Card>
        <CardHeader>
          <CardTitle>Plan Bonus Credits</CardTitle>
          <CardDescription>Bonus credits granted with subscription plans</CardDescription>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Plan</TableHead>
                <TableHead>Bonus Amount ($)</TableHead>
                <TableHead>Frequency</TableHead>
                <TableHead>Active</TableHead>
                <TableHead></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {bonuses.map((bonus, idx) => (
                <TableRow key={bonus.id}>
                  <TableCell className="font-medium capitalize">{bonus.subscription_plan}</TableCell>
                  <TableCell>
                    <Input
                      type="number"
                      step="1"
                      className="w-24 h-8"
                      value={(bonus.bonus_cents / 100).toFixed(0)}
                      onChange={(e) => {
                        const updated = [...bonuses]
                        updated[idx] = { ...bonus, bonus_cents: Math.round(parseFloat(e.target.value) * 100) || 0 }
                        setBonuses(updated)
                      }}
                    />
                  </TableCell>
                  <TableCell>
                    <Select
                      value={bonus.frequency}
                      onValueChange={(v) => {
                        const updated = [...bonuses]
                        updated[idx] = { ...bonus, frequency: v }
                        setBonuses(updated)
                      }}
                    >
                      <SelectTrigger className="w-28 h-8">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="one_time">One-time</SelectItem>
                        <SelectItem value="monthly">Monthly</SelectItem>
                      </SelectContent>
                    </Select>
                  </TableCell>
                  <TableCell>
                    <Badge variant={bonus.is_active ? 'default' : 'secondary'}>
                      {bonus.is_active ? 'Active' : 'Inactive'}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    <Button size="sm" variant="outline" onClick={() => saveBonus(bonus)} disabled={savingBonus}>
                      <Save className="h-3 w-3" />
                    </Button>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      {/* Showroom Balances */}
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>Showroom Balances</CardTitle>
              <CardDescription>Current credit balances for all showrooms</CardDescription>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          {balances.length === 0 ? (
            <p className="text-sm text-gray-500 py-4 text-center">No showrooms have credit balances yet</p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Showroom</TableHead>
                  <TableHead className="text-right">Balance</TableHead>
                  <TableHead></TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {balances.map((b) => (
                  <TableRow key={b.showroom_id}>
                    <TableCell className="font-medium">{b.showroom_name}</TableCell>
                    <TableCell className={`text-right font-medium ${b.balance_cents <= 0 ? 'text-red-600' : ''}`}>
                      ${(b.balance_cents / 100).toFixed(2)}
                    </TableCell>
                    <TableCell className="text-right">
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => {
                          setAddCreditsShowroom(b.showroom_id)
                          setAddCreditsOpen(true)
                        }}
                      >
                        <Plus className="h-3 w-3 mr-1" />
                        Add Credits
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {/* Transaction Log */}
      <Card>
        <CardHeader>
          <CardTitle>Transaction Log</CardTitle>
          <CardDescription>Recent transactions across all showrooms</CardDescription>
        </CardHeader>
        <CardContent>
          {transactions.length === 0 ? (
            <p className="text-sm text-gray-500 py-4 text-center">No transactions yet</p>
          ) : (
            <div className="max-h-[400px] overflow-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Date</TableHead>
                    <TableHead>Showroom</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead>Service</TableHead>
                    <TableHead>Notes</TableHead>
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
                        <TableCell className="text-sm">{txn.showroom_name}</TableCell>
                        <TableCell>
                          <Badge variant="outline" className="text-xs">
                            {txn.type.replace('_', ' ')}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-xs text-gray-500">
                          {txn.service_type?.replace('_', ' ') || '-'}
                        </TableCell>
                        <TableCell className="text-xs text-gray-500 max-w-[150px] truncate">
                          {txn.notes || '-'}
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
          )}
        </CardContent>
      </Card>

      {/* Add Credits Dialog */}
      <Dialog open={addCreditsOpen} onOpenChange={setAddCreditsOpen}>
        <DialogContent className="sm:max-w-[400px]">
          <DialogHeader>
            <DialogTitle>Add Credits</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-2">
              <Label>Amount ($)</Label>
              <Input
                type="number"
                step="1"
                min="1"
                placeholder="50"
                value={addCreditsAmount}
                onChange={(e) => setAddCreditsAmount(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label>Type</Label>
              <Select value={addCreditsType} onValueChange={setAddCreditsType}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="adjustment">Adjustment</SelectItem>
                  <SelectItem value="refund">Refund</SelectItem>
                  <SelectItem value="plan_bonus">Plan Bonus</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <Label>Notes (optional)</Label>
              <Input
                placeholder="Reason for adjustment..."
                value={addCreditsNotes}
                onChange={(e) => setAddCreditsNotes(e.target.value)}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setAddCreditsOpen(false)}>Cancel</Button>
            <Button onClick={handleAddCredits} disabled={addCreditsLoading || !addCreditsAmount}>
              {addCreditsLoading ? <Loader2 className="h-4 w-4 animate-spin mr-1" /> : <Plus className="h-4 w-4 mr-1" />}
              Add Credits
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
