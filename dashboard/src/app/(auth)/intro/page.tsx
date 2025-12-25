import Link from "next/link";
import Image from "next/image";
import {
  Ruler,
  Package,
  Palette,
  FolderKanban,
  CheckCircle,
  Mail,
  Smartphone,
  Monitor,
} from "lucide-react";

export default function IntroPage() {
  return (
    <div className="min-h-screen bg-white">
      {/* Navigation */}
      <nav className="fixed top-0 left-0 right-0 z-50 bg-white/80 backdrop-blur-md border-b border-gray-100">
        <div className="max-w-6xl mx-auto px-6 py-4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Image
              src="/logo.png"
              alt="CabinetScan Logo"
              width={40}
              height={40}
              className="w-10 h-10"
            />
            <span className="text-xl font-semibold text-gray-900">CabinetScan</span>
          </div>
          <Link
            href="/login"
            className="px-5 py-2.5 text-sm font-medium text-white rounded-full bg-gradient-to-r from-pink-500 via-purple-500 to-indigo-500 hover:opacity-90 transition-opacity"
          >
            Sign In
          </Link>
        </div>
      </nav>

      {/* Hero Section */}
      <section className="pt-32 pb-20 px-6">
        <div className="max-w-4xl mx-auto text-center">
          <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-green-50 text-green-700 text-sm font-medium mb-8">
            1 Week Free Trial
          </div>

          <h1 className="text-5xl md:text-6xl font-bold text-gray-900 leading-tight mb-6">
            Transform Your Cabinet Showroom with{" "}
            <span className="bg-gradient-to-r from-pink-500 via-purple-500 to-indigo-500 bg-clip-text text-transparent">
              3D Scanning
            </span>
          </h1>

          <p className="text-xl text-gray-600 mb-10 max-w-2xl mx-auto leading-relaxed">
            A complete two-platform solution: your customers scan rooms and select products
            via the iOS app, while you manage projects and access all details through the
            showroom dashboard.
          </p>

          </div>
      </section>

      {/* Two Platforms Section */}
      <section className="py-16 px-6 border-b border-gray-100">
        <div className="max-w-5xl mx-auto">
          <div className="grid md:grid-cols-2 gap-8">
            {/* Customer App */}
            <div className="relative p-8 rounded-2xl bg-gradient-to-br from-pink-50 via-purple-50 to-indigo-50 border border-purple-100">
              <div className="absolute -top-4 left-8">
                <span className="px-4 py-1.5 text-xs font-semibold text-white bg-gradient-to-r from-pink-500 to-purple-500 rounded-full">
                  FOR CUSTOMERS
                </span>
              </div>
              <div className="flex items-center gap-4 mb-4 mt-2">
                <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-pink-500 to-purple-500 flex items-center justify-center">
                  <Smartphone className="w-6 h-6 text-white" />
                </div>
                <h3 className="text-xl font-bold text-gray-900">iOS App</h3>
              </div>
              <p className="text-gray-600 mb-4">
                Your customers download the app, enter your showroom code, and start scanning their rooms with LiDAR technology.
              </p>
              <ul className="space-y-2 text-sm text-gray-600">
                <li className="flex items-center gap-2">
                  <CheckCircle className="w-4 h-4 text-purple-500" />
                  3D room scanning within ½ to ¾ inch accuracy
                </li>
                <li className="flex items-center gap-2">
                  <CheckCircle className="w-4 h-4 text-purple-500" />
                  Browse and select products from your catalog
                </li>
                <li className="flex items-center gap-2">
                  <CheckCircle className="w-4 h-4 text-purple-500" />
                  Submit projects with contact information
                </li>
              </ul>
            </div>

            {/* Showroom Dashboard */}
            <div className="relative p-8 rounded-2xl bg-gradient-to-br from-slate-900 to-slate-800 border border-slate-700">
              <div className="absolute -top-4 left-8">
                <span className="px-4 py-1.5 text-xs font-semibold text-white bg-gradient-to-r from-indigo-500 to-purple-500 rounded-full">
                  FOR SHOWROOMS
                </span>
              </div>
              <div className="flex items-center gap-4 mb-4 mt-2">
                <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-indigo-500 to-purple-500 flex items-center justify-center">
                  <Monitor className="w-6 h-6 text-white" />
                </div>
                <h3 className="text-xl font-bold text-white">Web Dashboard</h3>
              </div>
              <p className="text-gray-300 mb-4">
                Access every detail of customer projects in one place. Manage your catalog, branding, and turn submissions into quotes.
              </p>
              <ul className="space-y-2 text-sm text-gray-300">
                <li className="flex items-center gap-2">
                  <CheckCircle className="w-4 h-4 text-indigo-400" />
                  View all project submissions and customer details
                </li>
                <li className="flex items-center gap-2">
                  <CheckCircle className="w-4 h-4 text-indigo-400" />
                  Access room measurements and 3D scans
                </li>
                <li className="flex items-center gap-2">
                  <CheckCircle className="w-4 h-4 text-indigo-400" />
                  Manage products, categories, and pricing
                </li>
              </ul>
            </div>
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section className="py-20 px-6 bg-gradient-to-b from-gray-50 to-white">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-4">
              Everything You Need to Modernize Your Showroom
            </h2>
            <p className="text-lg text-gray-600 max-w-2xl mx-auto">
              A complete solution for cabinet showrooms to digitize their customer experience
            </p>
          </div>

          <div className="grid md:grid-cols-2 gap-6">
            {/* Feature 1 */}
            <div className="group p-8 bg-white rounded-2xl border border-gray-100 hover:border-pink-200 hover:shadow-xl hover:shadow-pink-500/5 transition-all">
              <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-pink-500 to-pink-600 flex items-center justify-center mb-6">
                <Ruler className="w-7 h-7 text-white" />
              </div>
              <h3 className="text-xl font-semibold text-gray-900 mb-3">Easy Measurements</h3>
              <p className="text-gray-600 leading-relaxed">
                LiDAR-powered 3D scanning delivers room measurements within ½ to ¾ inch accuracy.
                No more manual measuring or guesswork — get precise dimensions every time.
              </p>
            </div>

            {/* Feature 2 */}
            <div className="group p-8 bg-white rounded-2xl border border-gray-100 hover:border-purple-200 hover:shadow-xl hover:shadow-purple-500/5 transition-all">
              <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-purple-500 to-purple-600 flex items-center justify-center mb-6">
                <Package className="w-7 h-7 text-white" />
              </div>
              <h3 className="text-xl font-semibold text-gray-900 mb-3">Product Selection</h3>
              <p className="text-gray-600 leading-relaxed">
                Customers browse and select cabinet products right in the app.
                Your full catalog at their fingertips, organized by category for easy discovery.
              </p>
            </div>

            {/* Feature 3 */}
            <div className="group p-8 bg-white rounded-2xl border border-gray-100 hover:border-indigo-200 hover:shadow-xl hover:shadow-indigo-500/5 transition-all">
              <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-indigo-500 to-indigo-600 flex items-center justify-center mb-6">
                <Palette className="w-7 h-7 text-white" />
              </div>
              <h3 className="text-xl font-semibold text-gray-900 mb-3">White-label Branding</h3>
              <p className="text-gray-600 leading-relaxed">
                Your logo, colors, and showroom identity throughout the entire experience.
                Customers see your brand, not ours — building trust and recognition.
              </p>
            </div>

            {/* Feature 4 */}
            <div className="group p-8 bg-white rounded-2xl border border-gray-100 hover:border-pink-200 hover:shadow-xl hover:shadow-pink-500/5 transition-all">
              <div className="w-14 h-14 rounded-xl bg-gradient-to-br from-pink-500 via-purple-500 to-indigo-500 flex items-center justify-center mb-6">
                <FolderKanban className="w-7 h-7 text-white" />
              </div>
              <h3 className="text-xl font-semibold text-gray-900 mb-3">Project Management</h3>
              <p className="text-gray-600 leading-relaxed">
                Dashboard to track customer submissions, manage quotes, and follow up.
                All project data in one place — measurements, selections, and contact info.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* How It Works Section */}
      <section className="py-20 px-6">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-4">
              How It Works
            </h2>
            <p className="text-lg text-gray-600 max-w-2xl mx-auto">
              From showroom code to project submission in four simple steps
            </p>
          </div>

          <div className="grid md:grid-cols-4 gap-8">
            {/* Step 1 */}
            <div className="text-center">
              <div className="relative mb-6">
                <div className="w-16 h-16 mx-auto rounded-full bg-gradient-to-br from-pink-500 to-pink-600 flex items-center justify-center text-white text-2xl font-bold">
                  1
                </div>
                <div className="hidden md:block absolute top-8 left-[60%] w-full h-0.5 bg-gradient-to-r from-pink-300 to-purple-300"></div>
              </div>
              <h3 className="text-lg font-semibold text-gray-900 mb-2">Enter Showroom Code</h3>
              <p className="text-gray-600 text-sm">
                Customer enters your unique showroom code to access your branded experience
              </p>
            </div>

            {/* Step 2 */}
            <div className="text-center">
              <div className="relative mb-6">
                <div className="w-16 h-16 mx-auto rounded-full bg-gradient-to-br from-purple-500 to-purple-600 flex items-center justify-center text-white text-2xl font-bold">
                  2
                </div>
                <div className="hidden md:block absolute top-8 left-[60%] w-full h-0.5 bg-gradient-to-r from-purple-300 to-indigo-300"></div>
              </div>
              <h3 className="text-lg font-semibold text-gray-900 mb-2">Scan the Room</h3>
              <p className="text-gray-600 text-sm">
                iPhone LiDAR captures the space in minutes within ½ to ¾ inch precision
              </p>
            </div>

            {/* Step 3 */}
            <div className="text-center">
              <div className="relative mb-6">
                <div className="w-16 h-16 mx-auto rounded-full bg-gradient-to-br from-indigo-500 to-indigo-600 flex items-center justify-center text-white text-2xl font-bold">
                  3
                </div>
                <div className="hidden md:block absolute top-8 left-[60%] w-full h-0.5 bg-gradient-to-r from-indigo-300 to-pink-300"></div>
              </div>
              <h3 className="text-lg font-semibold text-gray-900 mb-2">Select Products</h3>
              <p className="text-gray-600 text-sm">
                Browse your catalog and choose cabinets, countertops, and more
              </p>
            </div>

            {/* Step 4 */}
            <div className="text-center">
              <div className="mb-6">
                <div className="w-16 h-16 mx-auto rounded-full bg-gradient-to-br from-pink-500 via-purple-500 to-indigo-500 flex items-center justify-center text-white text-2xl font-bold">
                  4
                </div>
              </div>
              <h3 className="text-lg font-semibold text-gray-900 mb-2">Receive the Project</h3>
              <p className="text-gray-600 text-sm">
                Get complete project data in your dashboard — ready to quote
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* First Touch Quote Section */}
      <section className="py-20 px-6 bg-gradient-to-br from-slate-900 via-purple-900 to-slate-900">
        <div className="max-w-4xl mx-auto text-center">
          <div className="w-16 h-16 mx-auto rounded-2xl bg-gradient-to-br from-pink-500 via-purple-500 to-indigo-500 flex items-center justify-center mb-8">
            <CheckCircle className="w-8 h-8 text-white" />
          </div>
          <h2 className="text-3xl md:text-4xl font-bold text-white mb-6">
            First Touch Quotes Made Easy
          </h2>
          <p className="text-xl text-gray-300 mb-8 leading-relaxed">
            With accurate measurements and product selections already captured,
            you can provide preliminary quotes faster than ever.
            Impress customers with quick turnaround and close more deals.
          </p>
          <div className="flex flex-wrap justify-center gap-6 text-left">
            <div className="flex items-start gap-3 text-gray-300">
              <CheckCircle className="w-5 h-5 text-pink-400 mt-0.5 flex-shrink-0" />
              <span>Accurate room dimensions</span>
            </div>
            <div className="flex items-start gap-3 text-gray-300">
              <CheckCircle className="w-5 h-5 text-purple-400 mt-0.5 flex-shrink-0" />
              <span>Product preferences captured</span>
            </div>
            <div className="flex items-start gap-3 text-gray-300">
              <CheckCircle className="w-5 h-5 text-indigo-400 mt-0.5 flex-shrink-0" />
              <span>Customer contact info ready</span>
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
            1 Week Free Trial
          </div>
          <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-4">
            Interested in CabinetScan?
          </h2>
          <p className="text-lg text-gray-600 mb-8">
            Try CabinetScan free for one week — no commitment required.
            Contact us to get started and transform your showroom experience.
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
