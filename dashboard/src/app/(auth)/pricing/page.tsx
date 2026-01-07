import Link from "next/link";
import Image from "next/image";
import { ArrowLeft, Check, Zap, Sparkles, Briefcase, Building2 } from "lucide-react";

const plans = [
  {
    name: "Starter",
    slug: "starter",
    price: 49,
    yearlyPrice: 470,
    description: "Scan-only plan for small showrooms",
    icon: Zap,
    iconColor: "from-blue-500 to-blue-600",
    retention: "30 days",
    features: [
      "20 projects/month",
      "3D room scanning",
      "Floor plans & measurements",
      "Photos & video capture",
      "5 GB storage",
      "1 team member",
      "30-day project retention",
      "Email support",
    ],
  },
  {
    name: "Pro",
    slug: "pro",
    price: 149,
    yearlyPrice: 1430,
    description: "For growing showrooms with product catalogs",
    icon: Sparkles,
    iconColor: "from-purple-500 to-purple-600",
    isFeatured: true,
    retention: "60 days",
    features: [
      "100 projects/month",
      "100 products",
      "Product selection in app",
      "AutoCAD/DXF export",
      "Custom branding",
      "50 GB storage",
      "3 team members",
      "60-day project retention",
      "Priority support",
    ],
  },
  {
    name: "Business",
    slug: "business",
    price: 249,
    yearlyPrice: 2390,
    description: "For power users with automation needs",
    icon: Briefcase,
    iconColor: "from-orange-500 to-orange-600",
    retention: "90 days",
    features: [
      "Unlimited projects",
      "300 products",
      "API & Webhook access",
      "AI-generated quotes",
      "Email quotes to customers",
      "Custom branding",
      "100 GB storage",
      "10 team members",
      "90-day project retention",
    ],
  },
  {
    name: "Enterprise",
    slug: "enterprise",
    price: null,
    description: "Custom solutions for large enterprises",
    icon: Building2,
    iconColor: "from-slate-700 to-slate-800",
    retention: "Forever",
    features: [
      "Everything in Business",
      "Unlimited products",
      "Unlimited storage",
      "Unlimited team members",
      "CRM integration",
      "White-label solution",
      "Dedicated account manager",
      "SLA guarantee",
    ],
  },
];

export default function PricingPage() {
  return (
    <div className="min-h-screen bg-white">
      {/* Navigation */}
      <nav className="fixed top-0 left-0 right-0 z-50 bg-white/80 backdrop-blur-md border-b border-gray-100">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 py-3 sm:py-4 flex items-center justify-between">
          <Link href="/intro" className="flex items-center gap-2 sm:gap-3">
            <Image
              src="/logo.png"
              alt="CabinetScan Logo"
              width={40}
              height={40}
              className="w-8 h-8 sm:w-10 sm:h-10"
            />
            <span className="hidden sm:inline text-xl font-semibold text-gray-900">CabinetScan</span>
          </Link>
          <div className="flex items-center gap-3 sm:gap-6">
            <Link
              href="/pricing"
              className="text-xs sm:text-sm font-medium text-purple-600"
            >
              Pricing
            </Link>
            <Link
              href="/contact"
              className="hidden sm:inline text-sm font-medium text-gray-700 hover:text-purple-600 transition-colors"
            >
              Contact
            </Link>
            <Link
              href="/login"
              className="px-3 sm:px-5 py-2 sm:py-2.5 text-xs sm:text-sm font-medium text-white rounded-full bg-gradient-to-r from-pink-500 via-purple-500 to-indigo-500 hover:opacity-90 transition-opacity"
            >
              Sign In
            </Link>
          </div>
        </div>
      </nav>

      {/* Main Content */}
      <main className="pt-32 pb-20 px-6">
        <div className="max-w-6xl mx-auto">
          {/* Back Link */}
          <Link
            href="/intro"
            className="inline-flex items-center gap-2 text-gray-600 hover:text-purple-600 transition-colors mb-8"
          >
            <ArrowLeft className="w-4 h-4" />
            Back to Home
          </Link>

          {/* Header */}
          <div className="text-center mb-16">
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-green-50 text-green-700 text-sm font-medium mb-6">
              14-Day Free Trial on All Plans
            </div>
            <h1 className="text-4xl md:text-5xl font-bold text-gray-900 mb-4">
              Simple, Transparent Pricing
            </h1>
            <p className="text-lg text-gray-600 max-w-2xl mx-auto">
              Choose the plan that fits your showroom. All plans include a 14-day free trial
              with full access to Pro features.
            </p>
          </div>

          {/* Pricing Cards */}
          <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-6 mb-16">
            {plans.map((plan) => {
              const Icon = plan.icon;
              return (
                <div
                  key={plan.slug}
                  className={`relative p-8 rounded-2xl bg-white border-2 transition-all flex flex-col ${
                    plan.isFeatured
                      ? "border-purple-500 shadow-xl shadow-purple-500/10"
                      : "border-gray-100 hover:border-gray-200"
                  }`}
                >
                  {plan.isFeatured && (
                    <div className="absolute -top-4 left-1/2 -translate-x-1/2">
                      <span className="px-4 py-1.5 text-xs font-semibold text-white bg-gradient-to-r from-pink-500 via-purple-500 to-indigo-500 rounded-full">
                        Most Popular
                      </span>
                    </div>
                  )}

                  <div className="flex items-center gap-3 mb-4">
                    <div className={`w-12 h-12 rounded-xl bg-gradient-to-br ${plan.iconColor} flex items-center justify-center`}>
                      <Icon className="w-6 h-6 text-white" />
                    </div>
                    <div>
                      <h3 className="text-xl font-bold text-gray-900">{plan.name}</h3>
                    </div>
                  </div>

                  <p className="text-gray-600 text-sm mb-6">{plan.description}</p>

                  <div className="mb-6">
                    {plan.price !== null ? (
                      <div className="flex items-baseline gap-1">
                        <span className="text-4xl font-bold text-gray-900">${plan.price}</span>
                        <span className="text-gray-500">/month</span>
                      </div>
                    ) : (
                      <div className="text-4xl font-bold text-gray-900">Custom</div>
                    )}
                  </div>

                  <div className="border-t border-gray-100 pt-6 mb-6 flex-grow">
                    <ul className="space-y-3">
                      {plan.features.map((feature, idx) => (
                        <li key={idx} className="flex items-start gap-3 text-sm text-gray-600">
                          <Check className={`w-5 h-5 flex-shrink-0 ${plan.isFeatured ? "text-purple-500" : "text-green-500"}`} />
                          {feature}
                        </li>
                      ))}
                    </ul>
                  </div>

                  {plan.slug === "enterprise" ? (
                    <a
                      href="mailto:contact@nextlyn.ai"
                      className="block w-full py-3 px-6 text-center font-semibold rounded-full bg-gray-900 text-white hover:bg-gray-800 transition-all mt-auto"
                    >
                      Contact Sales
                    </a>
                  ) : (
                    <Link
                      href="/contact"
                      className={`block w-full py-3 px-6 text-center font-semibold rounded-full transition-all mt-auto ${
                        plan.isFeatured
                          ? "bg-gradient-to-r from-pink-500 via-purple-500 to-indigo-500 text-white hover:shadow-lg hover:shadow-purple-500/25"
                          : "bg-gray-900 text-white hover:bg-gray-800"
                      }`}
                    >
                      Start Free Trial
                    </Link>
                  )}
                </div>
              );
            })}
          </div>

          {/* FAQ Section */}
          <div className="max-w-3xl mx-auto">
            <h2 className="text-2xl font-bold text-gray-900 mb-8 text-center">Frequently Asked Questions</h2>
            <div className="space-y-4">
              <div className="p-6 rounded-xl bg-gray-50 border border-gray-100">
                <h3 className="font-semibold text-gray-900 mb-2">Can I change plans later?</h3>
                <p className="text-gray-600 text-sm">
                  Yes, you can upgrade or downgrade your plan at any time. When upgrading, you&apos;ll get
                  immediate access to new features. When downgrading, changes take effect at the next billing cycle.
                </p>
              </div>
              <div className="p-6 rounded-xl bg-gray-50 border border-gray-100">
                <h3 className="font-semibold text-gray-900 mb-2">What happens after the free trial?</h3>
                <p className="text-gray-600 text-sm">
                  After your 14-day trial ends, you&apos;ll be prompted to choose a plan. Your data and
                  settings are preserved, and you can continue using CabinetScan by selecting a subscription.
                </p>
              </div>
              <div className="p-6 rounded-xl bg-gray-50 border border-gray-100">
                <h3 className="font-semibold text-gray-900 mb-2">Do you offer annual billing?</h3>
                <p className="text-gray-600 text-sm">
                  Yes! Save 20% with annual billing. Contact us or select the annual option when subscribing.
                </p>
              </div>
              <div className="p-6 rounded-xl bg-gray-50 border border-gray-100">
                <h3 className="font-semibold text-gray-900 mb-2">What payment methods do you accept?</h3>
                <p className="text-gray-600 text-sm">
                  We accept all major credit cards through our secure payment processor, Stripe. Enterprise
                  customers can also pay via invoice.
                </p>
              </div>
            </div>
          </div>
        </div>
      </main>

      {/* CTA Section */}
      <section className="py-16 px-6 bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900">
        <div className="max-w-2xl mx-auto text-center">
          <h2 className="text-3xl font-bold text-white mb-4">Ready to Transform Your Showroom?</h2>
          <p className="text-lg text-gray-300 mb-8">
            Start your free 14-day trial today. No credit card required.
          </p>
          <Link
            href="/contact"
            className="inline-flex items-center gap-2 px-8 py-4 text-lg font-semibold text-white rounded-full bg-gradient-to-r from-pink-500 via-purple-500 to-indigo-500 hover:shadow-lg hover:shadow-purple-500/25 transition-all"
          >
            Get Started Free
          </Link>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-8 px-6 border-t border-gray-100">
        <div className="max-w-6xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <Image
              src="/logo.png"
              alt="CabinetScan Logo"
              width={32}
              height={32}
              className="w-8 h-8"
            />
            <span className="text-sm text-gray-600">
              &copy; {new Date().getFullYear()} CabinetScan by Nextlyn
            </span>
          </div>
          <Link
            href="/intro"
            className="text-sm font-medium text-purple-600 hover:text-purple-700 transition-colors"
          >
            Back to Home
          </Link>
        </div>
      </footer>
    </div>
  );
}
