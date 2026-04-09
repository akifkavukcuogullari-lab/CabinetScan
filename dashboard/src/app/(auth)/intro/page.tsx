import Link from "next/link";
import Image from "next/image";
import {
  PhoneCall,
  CalendarCheck,
  Smartphone,
  Palette,
  Sparkles,
  FileCheck,
  CheckCircle,
  Mail,
  Zap,
  Users,
  Target,
  Workflow,
} from "lucide-react";

export default function IntroPage() {
  return (
    <div className="min-h-screen bg-white">
      {/* Navigation */}
      <nav className="fixed top-0 left-0 right-0 z-50 bg-white/80 backdrop-blur-md border-b border-gray-100">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 py-3 sm:py-4 flex items-center justify-between">
          <div className="flex items-center gap-2 sm:gap-3">
            <Image
              src="/logo.png"
              alt="CabinetScan Logo"
              width={40}
              height={40}
              className="w-8 h-8 sm:w-10 sm:h-10"
            />
            <span className="hidden sm:inline text-xl font-semibold text-gray-900">CabinetScan</span>
          </div>
          <div className="flex items-center gap-3 sm:gap-6">
            <Link
              href="/pricing"
              className="text-xs sm:text-sm font-medium text-gray-700 hover:text-purple-600 transition-colors"
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

      {/* Hero Section */}
      <section className="pt-32 pb-20 px-6">
        <div className="max-w-4xl mx-auto text-center">
          <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-green-50 text-green-700 text-sm font-medium mb-8">
            14-Day Free Trial
          </div>

          <h1 className="text-5xl md:text-6xl font-bold text-gray-900 leading-tight mb-6">
            From Lead to Close —{" "}
            <span className="bg-gradient-to-r from-pink-500 via-purple-500 to-indigo-500 bg-clip-text text-transparent">
              On Autopilot
            </span>
          </h1>

          <p className="text-xl text-gray-600 mb-10 max-w-2xl mx-auto leading-relaxed">
            CabinetScan is the end-to-end digital showroom platform. Capture the lead,
            automatically call and follow up, schedule the visit, gather every kitchen
            detail, and deliver a photorealistic 3D design — all in one pipeline.
          </p>
        </div>
      </section>

      {/* End-to-End Flow Section */}
      <section className="py-20 px-6 bg-gradient-to-b from-gray-50 to-white">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-4">
              Your Complete Sales Pipeline
            </h2>
            <p className="text-lg text-gray-600 max-w-2xl mx-auto">
              Every step from first contact to closing the deal — automated and connected.
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-6">
            {/* Step 1 - Lead Capture */}
            <div className="relative p-6 bg-white rounded-2xl border border-gray-100 shadow-sm hover:shadow-lg transition-shadow">
              <div className="absolute -top-3 -left-3 w-10 h-10 rounded-full bg-gradient-to-br from-pink-500 to-pink-600 flex items-center justify-center text-white font-bold text-sm shadow-md">
                1
              </div>
              <div className="w-12 h-12 rounded-xl bg-pink-50 flex items-center justify-center mb-4 mt-2">
                <Target className="w-6 h-6 text-pink-600" />
              </div>
              <h3 className="text-lg font-semibold text-gray-900 mb-2">Capture the Lead</h3>
              <p className="text-gray-600 text-sm leading-relaxed">
                Every new lead lands in your CabinetScan pipeline — from web forms,
                referrals, or your showroom.
              </p>
            </div>

            {/* Step 2 - AI Voice Agent */}
            <div className="relative p-6 bg-white rounded-2xl border border-gray-100 shadow-sm hover:shadow-lg transition-shadow">
              <div className="absolute -top-3 -left-3 w-10 h-10 rounded-full bg-gradient-to-br from-purple-500 to-purple-600 flex items-center justify-center text-white font-bold text-sm shadow-md">
                2
              </div>
              <div className="w-12 h-12 rounded-xl bg-purple-50 flex items-center justify-center mb-4 mt-2">
                <PhoneCall className="w-6 h-6 text-purple-600" />
              </div>
              <h3 className="text-lg font-semibold text-gray-900 mb-2">AI Calls & Follows Up</h3>
              <p className="text-gray-600 text-sm leading-relaxed">
                Our AI voice agent calls the homeowner or contractor and keeps following
                up via SMS and email until the customer responds.
              </p>
            </div>

            {/* Step 3 - Schedule Visit */}
            <div className="relative p-6 bg-white rounded-2xl border border-gray-100 shadow-sm hover:shadow-lg transition-shadow">
              <div className="absolute -top-3 -left-3 w-10 h-10 rounded-full bg-gradient-to-br from-indigo-500 to-indigo-600 flex items-center justify-center text-white font-bold text-sm shadow-md">
                3
              </div>
              <div className="w-12 h-12 rounded-xl bg-indigo-50 flex items-center justify-center mb-4 mt-2">
                <CalendarCheck className="w-6 h-6 text-indigo-600" />
              </div>
              <h3 className="text-lg font-semibold text-gray-900 mb-2">Schedule the Visit</h3>
              <p className="text-gray-600 text-sm leading-relaxed">
                The AI books an appointment at your showroom and invites the customer to
                download the CabinetScan app for their kitchen details.
              </p>
            </div>

            {/* Step 4 - Kitchen Details */}
            <div className="relative p-6 bg-white rounded-2xl border border-gray-100 shadow-sm hover:shadow-lg transition-shadow">
              <div className="absolute -top-3 -left-3 w-10 h-10 rounded-full bg-gradient-to-br from-blue-500 to-blue-600 flex items-center justify-center text-white font-bold text-sm shadow-md">
                4
              </div>
              <div className="w-12 h-12 rounded-xl bg-blue-50 flex items-center justify-center mb-4 mt-2">
                <Smartphone className="w-6 h-6 text-blue-600" />
              </div>
              <h3 className="text-lg font-semibold text-gray-900 mb-2">Capture Kitchen Details</h3>
              <p className="text-gray-600 text-sm leading-relaxed">
                Customers scan their kitchen — measurements, video walkthroughs, photos,
                and product selections, all captured in one app.
              </p>
            </div>

            {/* Step 5 - Designer Handoff */}
            <div className="relative p-6 bg-white rounded-2xl border border-gray-100 shadow-sm hover:shadow-lg transition-shadow">
              <div className="absolute -top-3 -left-3 w-10 h-10 rounded-full bg-gradient-to-br from-teal-500 to-teal-600 flex items-center justify-center text-white font-bold text-sm shadow-md">
                5
              </div>
              <div className="w-12 h-12 rounded-xl bg-teal-50 flex items-center justify-center mb-4 mt-2">
                <Workflow className="w-6 h-6 text-teal-600" />
              </div>
              <h3 className="text-lg font-semibold text-gray-900 mb-2">Instant Designer Handoff</h3>
              <p className="text-gray-600 text-sm leading-relaxed">
                Every project detail submits instantly to our professional designer
                network — no manual transfers or missing info.
              </p>
            </div>

            {/* Step 6 - 3D + Render */}
            <div className="relative p-6 bg-white rounded-2xl border border-gray-100 shadow-sm hover:shadow-lg transition-shadow">
              <div className="absolute -top-3 -left-3 w-10 h-10 rounded-full bg-gradient-to-br from-orange-500 to-orange-600 flex items-center justify-center text-white font-bold text-sm shadow-md">
                6
              </div>
              <div className="w-12 h-12 rounded-xl bg-orange-50 flex items-center justify-center mb-4 mt-2">
                <Sparkles className="w-6 h-6 text-orange-600" />
              </div>
              <h3 className="text-lg font-semibold text-gray-900 mb-2">3D Design + Photoreal Render</h3>
              <p className="text-gray-600 text-sm leading-relaxed">
                Designers deliver a 3D kitchen design and photorealistic renders so
                customers visualize their future kitchen before signing.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Why It Works Section */}
      <section className="py-20 px-6">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-4">
              Why Showrooms Choose CabinetScan
            </h2>
            <p className="text-lg text-gray-600 max-w-2xl mx-auto">
              One platform replaces the messy handoffs between lead, sales, design, and closing.
            </p>
          </div>

          <div className="grid md:grid-cols-2 gap-6">
            {/* Never Lose a Lead */}
            <div className="group p-8 bg-white rounded-2xl border border-gray-100 hover:border-purple-200 hover:shadow-xl hover:shadow-purple-500/5 transition-all">
              <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-purple-500 to-purple-600 flex items-center justify-center mb-6">
                <PhoneCall className="w-7 h-7 text-white" />
              </div>
              <h3 className="text-xl font-semibold text-gray-900 mb-3">Never Lose a Lead</h3>
              <p className="text-gray-600 leading-relaxed">
                Our AI voice agent calls and follows up automatically until the customer
                responds. No missed opportunities, no ghosted leads, no manual dialing.
              </p>
            </div>

            {/* Everything in One App */}
            <div className="group p-8 bg-white rounded-2xl border border-gray-100 hover:border-blue-200 hover:shadow-xl hover:shadow-blue-500/5 transition-all">
              <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-blue-500 to-blue-600 flex items-center justify-center mb-6">
                <Smartphone className="w-7 h-7 text-white" />
              </div>
              <h3 className="text-xl font-semibold text-gray-900 mb-3">Everything in One App</h3>
              <p className="text-gray-600 leading-relaxed">
                Customers capture every detail through the CabinetScan app — measurements,
                videos, photos, and product selections — all in one seamless flow.
              </p>
            </div>

            {/* Professional Designer Network */}
            <div className="group p-8 bg-white rounded-2xl border border-gray-100 hover:border-teal-200 hover:shadow-xl hover:shadow-teal-500/5 transition-all">
              <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-teal-500 to-teal-600 flex items-center justify-center mb-6">
                <Users className="w-7 h-7 text-white" />
              </div>
              <h3 className="text-xl font-semibold text-gray-900 mb-3">Professional Designer Network</h3>
              <p className="text-gray-600 leading-relaxed">
                Skip hiring in-house designers. Our on-demand network delivers 3D designs
                in hours — with multiple priority tiers to match your timeline.
              </p>
            </div>

            {/* Photorealistic Renders */}
            <div className="group p-8 bg-white rounded-2xl border border-gray-100 hover:border-orange-200 hover:shadow-xl hover:shadow-orange-500/5 transition-all">
              <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-orange-500 to-orange-600 flex items-center justify-center mb-6">
                <Palette className="w-7 h-7 text-white" />
              </div>
              <h3 className="text-xl font-semibold text-gray-900 mb-3">Photorealistic Renders</h3>
              <p className="text-gray-600 leading-relaxed">
                Customers see their exact future kitchen — not a generic catalog photo.
                Visualization drives emotion, and emotion closes deals.
              </p>
            </div>

            {/* Accurate Quotes from Design */}
            <div className="group p-8 bg-white rounded-2xl border border-gray-100 hover:border-green-200 hover:shadow-xl hover:shadow-green-500/5 transition-all">
              <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-green-500 to-green-600 flex items-center justify-center mb-6">
                <FileCheck className="w-7 h-7 text-white" />
              </div>
              <h3 className="text-xl font-semibold text-gray-900 mb-3">Accurate Quotes from Design</h3>
              <p className="text-gray-600 leading-relaxed">
                Quotes are generated from the actual design — not rough estimates.
                No guesswork, no surprises, and a price your customer can trust.
              </p>
            </div>

            {/* One Pipeline, Zero Chaos */}
            <div className="group p-8 bg-white rounded-2xl border border-gray-100 hover:border-pink-200 hover:shadow-xl hover:shadow-pink-500/5 transition-all">
              <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-pink-500 via-purple-500 to-indigo-500 flex items-center justify-center mb-6">
                <Zap className="w-7 h-7 text-white" />
              </div>
              <h3 className="text-xl font-semibold text-gray-900 mb-3">One Pipeline, Zero Chaos</h3>
              <p className="text-gray-600 leading-relaxed">
                Lead → call → visit → scan → design → render → quote → close. Every step
                in one dashboard. No spreadsheets, no copy-paste, no dropped handoffs.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Close More Deals Section */}
      <section className="py-20 px-6 bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900">
        <div className="max-w-4xl mx-auto text-center">
          <div className="w-16 h-16 mx-auto rounded-2xl bg-gradient-to-br from-pink-500 via-purple-500 to-indigo-500 flex items-center justify-center mb-8">
            <CheckCircle className="w-8 h-8 text-white" />
          </div>
          <h2 className="text-3xl md:text-4xl font-bold text-white mb-6">
            Close More Deals, Faster
          </h2>
          <p className="text-xl text-gray-300 mb-8 leading-relaxed">
            Stop losing leads to slow follow-up and manual handoffs. CabinetScan automates
            the entire pipeline from first contact to closed deal — so you can focus on
            building relationships, not chasing paperwork.
          </p>
          <div className="grid sm:grid-cols-3 gap-6 text-left">
            <div className="flex items-start gap-3 text-gray-300">
              <CheckCircle className="w-5 h-5 text-pink-400 mt-0.5 flex-shrink-0" />
              <span>Automated lead follow-up</span>
            </div>
            <div className="flex items-start gap-3 text-gray-300">
              <CheckCircle className="w-5 h-5 text-purple-400 mt-0.5 flex-shrink-0" />
              <span>Instant designer handoff</span>
            </div>
            <div className="flex items-start gap-3 text-gray-300">
              <CheckCircle className="w-5 h-5 text-indigo-400 mt-0.5 flex-shrink-0" />
              <span>Photorealistic 3D renders</span>
            </div>
          </div>
        </div>
      </section>

      {/* Contact Section */}
      <section className="py-20 px-6">
        <div className="max-w-2xl mx-auto text-center">
          <div className="w-16 h-16 mx-auto rounded-2xl bg-gradient-to-br from-pink-100 via-purple-100 to-indigo-100 flex items-center justify-center mb-8">
            <Mail className="w-8 h-8 text-purple-600" />
          </div>
          <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-gradient-to-r from-pink-100 via-purple-100 to-indigo-100 text-purple-700 text-sm font-semibold mb-6">
            14-Day Free Trial
          </div>
          <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-4">
            Ready to Automate Your Showroom?
          </h2>
          <p className="text-lg text-gray-600 mb-8">
            Try CabinetScan free for 14 days — no credit card required.
            Contact us to get started and turn every lead into a closed deal.
          </p>
          <a
            href="mailto:contact@nextlyn.ai"
            className="inline-flex items-center gap-3 px-8 py-4 text-lg font-semibold text-white rounded-full bg-gradient-to-r from-pink-500 via-purple-500 to-indigo-500 hover:shadow-lg hover:shadow-purple-500/25 transition-all"
          >
            <Mail className="w-5 h-5" />
            contact@nextlyn.ai
          </a>
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
            href="/login"
            className="text-sm font-medium text-purple-600 hover:text-purple-700 transition-colors"
          >
            Sign in to Dashboard →
          </Link>
        </div>
      </footer>
    </div>
  );
}
