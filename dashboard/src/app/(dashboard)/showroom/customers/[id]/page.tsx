import { createClient } from '@/lib/supabase/server'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  ArrowLeft, User, Phone, Mail, MapPin,
  FolderKanban, Building, Home
} from 'lucide-react'
import Link from 'next/link'
import { redirect, notFound } from 'next/navigation'

interface CustomerDetailPageProps {
  params: Promise<{ id: string }>
}

export default async function CustomerDetailPage({ params }: CustomerDetailPageProps) {
  const { id } = await params
  const supabase = await createClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  // Get the user's showroom
  const { data: showroomUser } = await supabase
    .from('showroom_users')
    .select('showroom_id')
    .eq('user_id', user.id)
    .single()

  if (!showroomUser) redirect('/login')

  // Get customer details
  const { data: customer, error } = await supabase
    .from('customers')
    .select('*')
    .eq('id', id)
    .eq('showroom_id', showroomUser.showroom_id)
    .single()

  if (error || !customer) {
    notFound()
  }

  // Get customer's projects with measurements
  const { data: projects } = await supabase
    .from('projects')
    .select(`
      *,
      project_measurements (
        id,
        usdz_file_url,
        preview_image_url,
        total_linear_ft,
        total_sq_ft
      )
    `)
    .eq('customer_id', id)
    .order('submitted_at', { ascending: false })

  const customerTypeColors: Record<string, string> = {
    homeowner: 'bg-blue-100 text-blue-800',
    contractor: 'bg-purple-100 text-purple-800',
  }

  const statusColors: Record<string, string> = {
    draft: 'bg-gray-100 text-gray-800',
    submitted: 'bg-blue-100 text-blue-800',
    in_review: 'bg-yellow-100 text-yellow-800',
    quoted: 'bg-purple-100 text-purple-800',
    accepted: 'bg-green-100 text-green-800',
    rejected: 'bg-red-100 text-red-800',
    completed: 'bg-green-100 text-green-800',
  }

  const TypeIcon = customer.customer_type === 'contractor' ? Building : Home

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center gap-4">
        <Link href="/showroom/customers">
          <Button variant="ghost" size="sm">
            <ArrowLeft className="h-4 w-4 mr-2" />
            Back to Customers
          </Button>
        </Link>
      </div>

      {/* Customer Profile Card */}
      <Card>
        <CardHeader>
          <div className="flex items-start justify-between">
            <div className="flex items-center gap-4">
              <div className="w-16 h-16 rounded-full bg-gray-100 flex items-center justify-center">
                <User className="h-8 w-8 text-gray-400" />
              </div>
              <div>
                <CardTitle className="text-2xl">
                  {customer.first_name} {customer.last_name}
                </CardTitle>
                <Badge className={`${customerTypeColors[customer.customer_type]} capitalize mt-1`}>
                  <TypeIcon className="h-3 w-3 mr-1" />
                  {customer.customer_type}
                </Badge>
              </div>
            </div>
            <div className="text-right text-sm text-gray-500">
              <div>Customer since</div>
              <div className="font-medium text-gray-900">
                {new Date(customer.created_at).toLocaleDateString('en-US', {
                  month: 'long',
                  day: 'numeric',
                  year: 'numeric'
                })}
              </div>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
            {/* Phone */}
            <div className="flex items-start gap-3">
              <Phone className="h-5 w-5 text-gray-400 mt-0.5" />
              <div>
                <div className="text-sm text-gray-500">Phone</div>
                <div className="font-medium">{customer.phone}</div>
              </div>
            </div>

            {/* Email */}
            {customer.email && (
              <div className="flex items-start gap-3">
                <Mail className="h-5 w-5 text-gray-400 mt-0.5" />
                <div>
                  <div className="text-sm text-gray-500">Email</div>
                  <div className="font-medium">{customer.email}</div>
                </div>
              </div>
            )}

            {/* Address */}
            {customer.address_line1 && (
              <div className="flex items-start gap-3">
                <MapPin className="h-5 w-5 text-gray-400 mt-0.5" />
                <div>
                  <div className="text-sm text-gray-500">Address</div>
                  <div className="font-medium">
                    {customer.address_line1}
                    {customer.city && customer.state && (
                      <div className="text-gray-600">
                        {customer.city}, {customer.state} {customer.zip_code}
                      </div>
                    )}
                  </div>
                </div>
              </div>
            )}

            {/* Projects count */}
            <div className="flex items-start gap-3">
              <FolderKanban className="h-5 w-5 text-gray-400 mt-0.5" />
              <div>
                <div className="text-sm text-gray-500">Total Projects</div>
                <div className="font-medium">{projects?.length || 0}</div>
              </div>
            </div>
          </div>

          {/* Notes */}
          {customer.notes && (
            <div className="mt-6 pt-6 border-t">
              <div className="text-sm text-gray-500 mb-1">Notes</div>
              <div className="text-gray-700">{customer.notes}</div>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Projects Section */}
      <div>
        <h2 className="text-xl font-semibold mb-4">Project History</h2>

        {projects && projects.length > 0 ? (
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4 gap-4">
            {projects.map((project: any) => {
              return (
                <Link
                  key={project.id}
                  href={`/showroom/projects/${project.id}`}
                  className="group"
                >
                  <Card className="h-full hover:shadow-md transition-all duration-200 hover:border-blue-400">
                    <CardContent className="p-4">
                      {/* Header: Project Name + Status */}
                      <div className="flex items-start justify-between gap-2 mb-2">
                        <div className="flex-1 min-w-0">
                          <h3 className="font-semibold truncate group-hover:text-blue-600 transition-colors">
                            {project.project_name || 'Room Scan'}
                          </h3>
                          <div className="flex items-center gap-2 text-xs text-gray-500">
                            <code className="font-mono">{project.reference_number}</code>
                            <span>|</span>
                            <span>
                              {project.submitted_at
                                ? new Date(project.submitted_at).toLocaleDateString('en-US', {
                                    month: 'short',
                                    day: 'numeric'
                                  })
                                : '-'}
                            </span>
                          </div>
                        </div>
                        <Badge className={`${statusColors[project.status]} shrink-0 text-xs`}>
                          {project.status.replace('_', ' ')}
                        </Badge>
                      </div>
                    </CardContent>
                  </Card>
                </Link>
              )
            })}
          </div>
        ) : (
          <Card>
            <CardContent className="py-10 text-center">
              <FolderKanban className="h-10 w-10 text-gray-300 mx-auto mb-3" />
              <p className="text-gray-500">No projects from this customer yet</p>
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  )
}
