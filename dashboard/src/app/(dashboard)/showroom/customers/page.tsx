import { createClient } from '@/lib/supabase/server'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Users, Phone, Mail, MapPin, Calendar, ChevronRight, FolderKanban, Building, Home } from 'lucide-react'
import Link from 'next/link'
import { redirect } from 'next/navigation'

export default async function CustomersPage() {
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

  // Get customers with project count
  const { data: customers, error } = await supabase
    .from('customers')
    .select(`
      *,
      projects (id)
    `)
    .eq('showroom_id', showroomUser.showroom_id)
    .order('created_at', { ascending: false })

  const customerTypeColors: Record<string, string> = {
    homeowner: 'bg-blue-100 text-blue-800',
    contractor: 'bg-purple-100 text-purple-800',
  }

  const customerTypeIcons: Record<string, typeof Home> = {
    homeowner: Home,
    contractor: Building,
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Customers</h1>
        <p className="text-gray-500">View and manage your customers and their projects</p>
      </div>

      {error ? (
        <Card>
          <CardContent className="py-10 text-center text-red-600">
            Error loading customers: {error.message}
          </CardContent>
        </Card>
      ) : customers && customers.length > 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
          {customers.map((customer: any) => {
            const projectCount = customer.projects?.length || 0
            const TypeIcon = customerTypeIcons[customer.customer_type] || Home

            return (
              <Link
                key={customer.id}
                href={`/showroom/customers/${customer.id}`}
                className="group"
              >
                <Card className="h-full overflow-hidden hover:shadow-lg transition-all duration-200 hover:border-blue-400">
                  <CardContent className="p-5">
                    {/* Header with name and type */}
                    <div className="flex items-start justify-between mb-4">
                      <div className="flex-1 min-w-0">
                        <h3 className="font-semibold text-lg truncate group-hover:text-blue-600 transition-colors">
                          {customer.first_name} {customer.last_name}
                        </h3>
                        <div className="flex items-center gap-2 mt-1">
                          <Badge className={`${customerTypeColors[customer.customer_type]} capitalize`}>
                            <TypeIcon className="h-3 w-3 mr-1" />
                            {customer.customer_type}
                          </Badge>
                          <span className="text-sm text-gray-500">
                            {projectCount} project{projectCount !== 1 ? 's' : ''}
                          </span>
                        </div>
                      </div>
                    </div>

                    {/* Contact info */}
                    <div className="space-y-2 text-sm text-gray-600">
                      <div className="flex items-center gap-2">
                        <Phone className="h-4 w-4 text-gray-400" />
                        <span className="truncate">{customer.phone}</span>
                      </div>

                      {customer.email && (
                        <div className="flex items-center gap-2">
                          <Mail className="h-4 w-4 text-gray-400" />
                          <span className="truncate">{customer.email}</span>
                        </div>
                      )}

                      {customer.address_line1 && (
                        <div className="flex items-center gap-2">
                          <MapPin className="h-4 w-4 text-gray-400" />
                          <span className="truncate">
                            {customer.city && customer.state
                              ? `${customer.city}, ${customer.state}`
                              : customer.address_line1}
                          </span>
                        </div>
                      )}

                      <div className="flex items-center gap-2">
                        <Calendar className="h-4 w-4 text-gray-400" />
                        <span>
                          Customer since {new Date(customer.created_at).toLocaleDateString('en-US', {
                            month: 'short',
                            day: 'numeric',
                            year: 'numeric'
                          })}
                        </span>
                      </div>
                    </div>

                    {/* View button */}
                    <div className="mt-4 pt-3 border-t flex items-center justify-between">
                      <div className="flex items-center gap-1 text-sm text-gray-500">
                        <FolderKanban className="h-4 w-4" />
                        <span>{projectCount} project{projectCount !== 1 ? 's' : ''}</span>
                      </div>
                      <Button
                        variant="ghost"
                        size="sm"
                        className="text-blue-600 hover:text-blue-700 hover:bg-blue-50 -mr-2"
                      >
                        View
                        <ChevronRight className="h-4 w-4 ml-1" />
                      </Button>
                    </div>
                  </CardContent>
                </Card>
              </Link>
            )
          })}
        </div>
      ) : (
        <Card>
          <CardContent className="py-16 text-center">
            <div className="w-20 h-20 rounded-full bg-gray-100 flex items-center justify-center mx-auto mb-6">
              <Users className="h-10 w-10 text-gray-400" />
            </div>
            <h3 className="text-xl font-medium mb-2">No customers yet</h3>
            <p className="text-gray-500 max-w-md mx-auto mb-6">
              Customers will appear here when they submit projects from the iOS app.
              Each customer is identified by their phone number.
            </p>
            <div className="flex flex-col sm:flex-row items-center justify-center gap-4 text-sm text-gray-500">
              <div className="flex items-center gap-2">
                <Home className="h-5 w-5 text-blue-500" />
                <span>Homeowners</span>
              </div>
              <div className="flex items-center gap-2">
                <Building className="h-5 w-5 text-purple-500" />
                <span>Contractors</span>
              </div>
              <div className="flex items-center gap-2">
                <FolderKanban className="h-5 w-5 text-green-500" />
                <span>Project History</span>
              </div>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
