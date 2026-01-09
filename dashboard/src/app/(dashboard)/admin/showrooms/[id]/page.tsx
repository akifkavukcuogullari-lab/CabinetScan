import { createClient } from '@/lib/supabase/server'
import { notFound } from 'next/navigation'
import Link from 'next/link'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { ArrowLeft, Copy, ExternalLink, Users, Package, FolderKanban, Mail, HardDrive, TrendingUp, Bot } from 'lucide-react'
import { InvitationList } from '@/components/invitations/invitation-list'
import { SubscriptionManager } from '@/components/admin/subscription-manager'
import { DesignerAgentSettings } from '@/components/admin/designer-agent-settings'

interface ShowroomDetailPageProps {
  params: Promise<{ id: string }>
}

export default async function ShowroomDetailPage({ params }: ShowroomDetailPageProps) {
  const { id } = await params
  const supabase = await createClient()

  const { data: showroom, error } = await supabase
    .from('showrooms')
    .select('*')
    .eq('id', id)
    .single()

  if (error || !showroom) {
    notFound()
  }

  // Get stats
  const { count: productCount } = await supabase
    .from('products')
    .select('*', { count: 'exact', head: true })
    .eq('showroom_id', id)

  const { count: projectCount } = await supabase
    .from('projects')
    .select('*', { count: 'exact', head: true })
    .eq('showroom_id', id)

  const { count: userCount } = await supabase
    .from('showroom_users')
    .select('*', { count: 'exact', head: true })
    .eq('showroom_id', id)
    .eq('is_active', true)

  // Get pending invitation count
  const { count: pendingInvitations } = await supabase
    .from('showroom_invitations')
    .select('*', { count: 'exact', head: true })
    .eq('showroom_id', id)
    .eq('status', 'pending')

  // Get usage metrics
  const { data: usageMetrics } = await supabase
    .from('showroom_usage_summary')
    .select('total_projects, projects_last_month, total_storage_bytes, storage_last_month_bytes')
    .eq('id', id)
    .single()

  const formatStorageGB = (bytes: number) => {
    const gb = bytes / (1024 * 1024 * 1024)
    return gb.toFixed(2)
  }

  const statusColors: Record<string, string> = {
    trial: 'bg-yellow-100 text-yellow-800',
    active: 'bg-green-100 text-green-800',
    past_due: 'bg-red-100 text-red-800',
    canceled: 'bg-gray-100 text-gray-800',
    suspended: 'bg-red-100 text-red-800',
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-4">
        <Link href="/admin/showrooms">
          <Button variant="ghost" size="icon">
            <ArrowLeft className="h-5 w-5" />
          </Button>
        </Link>
        <div className="flex-1">
          <div className="flex items-center gap-3">
            <h1 className="text-2xl font-bold">{showroom.name}</h1>
            <Badge className={statusColors[showroom.subscription_status]}>
              {showroom.subscription_status}
            </Badge>
          </div>
          <p className="text-gray-500">{showroom.email}</p>
        </div>
        <Link href={`/admin/showrooms/${id}/edit`}>
          <Button variant="outline">Edit Showroom</Button>
        </Link>
      </div>

      {/* Showroom Code Card */}
      <Card className="bg-blue-50 border-blue-200">
        <CardContent className="py-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-blue-600 font-medium">Showroom Code</p>
              <p className="text-3xl font-mono font-bold text-blue-900">
                {showroom.showroom_code}
              </p>
              <p className="text-sm text-blue-600 mt-1">
                Customers enter this code in the iOS app
              </p>
            </div>
            <Button variant="outline" size="sm" className="gap-2">
              <Copy className="h-4 w-4" />
              Copy Code
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <Card>
          <CardContent className="py-6">
            <div className="flex items-center gap-4">
              <div className="p-3 bg-blue-100 rounded-lg">
                <Package className="h-6 w-6 text-blue-600" />
              </div>
              <div>
                <p className="text-2xl font-bold">{productCount || 0}</p>
                <p className="text-sm text-gray-500">Products</p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="py-6">
            <div className="flex items-center gap-4">
              <div className="p-3 bg-green-100 rounded-lg">
                <FolderKanban className="h-6 w-6 text-green-600" />
              </div>
              <div>
                <p className="text-2xl font-bold">{projectCount || 0}</p>
                <p className="text-sm text-gray-500">Projects</p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="py-6">
            <div className="flex items-center gap-4">
              <div className="p-3 bg-purple-100 rounded-lg">
                <Users className="h-6 w-6 text-purple-600" />
              </div>
              <div>
                <p className="text-2xl font-bold">{userCount || 0}</p>
                <p className="text-sm text-gray-500">Team Members</p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="py-6">
            <div className="flex items-center gap-4">
              <div className="p-3 bg-yellow-100 rounded-lg">
                <Mail className="h-6 w-6 text-yellow-600" />
              </div>
              <div>
                <p className="text-2xl font-bold">{pendingInvitations || 0}</p>
                <p className="text-sm text-gray-500">Pending Invites</p>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Details Tabs */}
      <Tabs defaultValue="details">
        <TabsList>
          <TabsTrigger value="details">Details</TabsTrigger>
          <TabsTrigger value="users">
            Users & Invitations
            {(pendingInvitations || 0) > 0 && (
              <Badge variant="secondary" className="ml-2 h-5 w-5 rounded-full p-0 text-xs">
                {pendingInvitations}
              </Badge>
            )}
          </TabsTrigger>
          <TabsTrigger value="subscription">Subscription</TabsTrigger>
          <TabsTrigger value="designer-agent" className="gap-1.5">
            <Bot className="h-4 w-4" />
            Designer Agent
          </TabsTrigger>
        </TabsList>

        <TabsContent value="details" className="mt-4 space-y-4">
          {/* Usage Metrics Card */}
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <TrendingUp className="h-5 w-5" />
                Monthly Usage Metrics
              </CardTitle>
              <CardDescription>
                Project submissions and storage consumption tracking
              </CardDescription>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                {/* Projects Usage */}
                <div className="space-y-3">
                  <div className="flex items-center gap-2 text-sm font-medium text-gray-700">
                    <FolderKanban className="h-4 w-4" />
                    Project Submissions
                  </div>
                  <div className="grid grid-cols-2 gap-4">
                    <div className="bg-blue-50 rounded-lg p-4 border border-blue-100">
                      <p className="text-xs text-blue-600 font-medium mb-1">Total Projects</p>
                      <p className="text-3xl font-bold text-blue-900">
                        {usageMetrics?.total_projects || 0}
                      </p>
                    </div>
                    <div className="bg-purple-50 rounded-lg p-4 border border-purple-100">
                      <p className="text-xs text-purple-600 font-medium mb-1">Last Month</p>
                      <p className="text-3xl font-bold text-purple-900">
                        {usageMetrics?.projects_last_month || 0}
                      </p>
                    </div>
                  </div>
                </div>

                {/* Storage Usage */}
                <div className="space-y-3">
                  <div className="flex items-center gap-2 text-sm font-medium text-gray-700">
                    <HardDrive className="h-4 w-4" />
                    Storage Consumption
                  </div>
                  <div className="grid grid-cols-2 gap-4">
                    <div className="bg-green-50 rounded-lg p-4 border border-green-100">
                      <p className="text-xs text-green-600 font-medium mb-1">Total Storage</p>
                      <p className="text-3xl font-bold text-green-900">
                        {formatStorageGB(usageMetrics?.total_storage_bytes || 0)}
                      </p>
                      <p className="text-xs text-green-600 mt-1">GB</p>
                    </div>
                    <div className="bg-orange-50 rounded-lg p-4 border border-orange-100">
                      <p className="text-xs text-orange-600 font-medium mb-1">Last Month</p>
                      <p className="text-3xl font-bold text-orange-900">
                        {formatStorageGB(usageMetrics?.storage_last_month_bytes || 0)}
                      </p>
                      <p className="text-xs text-orange-600 mt-1">GB</p>
                    </div>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Business Information Card */}
          <Card>
            <CardHeader>
              <CardTitle>Business Information</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-sm text-gray-500">Slug</p>
                  <p className="font-mono">{showroom.slug}</p>
                </div>
                <div>
                  <p className="text-sm text-gray-500">Phone</p>
                  <p>{showroom.phone || '-'}</p>
                </div>
              </div>

              <div>
                <p className="text-sm text-gray-500">Address</p>
                <p>
                  {[
                    showroom.address_line1,
                    showroom.address_line2,
                    showroom.city,
                    showroom.state,
                    showroom.postal_code,
                  ]
                    .filter(Boolean)
                    .join(', ') || '-'}
                </p>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-sm text-gray-500">Timezone</p>
                  <p>{showroom.timezone}</p>
                </div>
                <div>
                  <p className="text-sm text-gray-500">Currency</p>
                  <p>{showroom.currency}</p>
                </div>
              </div>

              <div>
                <p className="text-sm text-gray-500">Created</p>
                <p>{new Date(showroom.created_at).toLocaleString()}</p>
              </div>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="users" className="mt-4">
          <Card>
            <CardHeader>
              <CardTitle>Team Members & Invitations</CardTitle>
              <CardDescription>
                Manage users who can access this showroom and pending invitations
              </CardDescription>
            </CardHeader>
            <CardContent>
              <InvitationList showroomId={id} />
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="subscription" className="mt-4">
          <SubscriptionManager
            showroom={{
              id: showroom.id,
              name: showroom.name,
              subscription_status: showroom.subscription_status,
              subscription_plan: showroom.subscription_plan,
              trial_ends_at: showroom.trial_ends_at,
              stripe_customer_id: showroom.stripe_customer_id,
              stripe_subscription_id: showroom.stripe_subscription_id,
            }}
          />
        </TabsContent>

        <TabsContent value="designer-agent" className="mt-4">
          <DesignerAgentSettings
            showroom={{
              id: showroom.id,
              name: showroom.name,
              ai_chatbot_enabled: showroom.ai_chatbot_enabled ?? false,
            }}
          />
        </TabsContent>
      </Tabs>
    </div>
  )
}
