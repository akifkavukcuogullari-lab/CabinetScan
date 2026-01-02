import Link from "next/link";
import Image from "next/image";
import { Mail, MessageCircle, Clock, ArrowLeft, Sparkles } from "lucide-react";

export default function ContactPage() {
  return (
    <div className="min-h-screen bg-white">
      {/* Navigation */}
      <nav className="fixed top-0 left-0 right-0 z-50 bg-white/80 backdrop-blur-md border-b border-gray-100">
        <div className="max-w-6xl mx-auto px-6 py-4 flex items-center justify-between">
          <Link href="/intro" className="flex items-center gap-3">
            <Image
              src="/logo.png"
              alt="CabinetScan Logo"
              width={40}
              height={40}
              className="w-10 h-10"
            />
            <span className="text-xl font-semibold text-gray-900">CabinetScan</span>
          </Link>
          <Link
            href="/login"
            className="px-5 py-2.5 text-sm font-medium text-white rounded-full bg-gradient-to-r from-pink-500 via-purple-500 to-indigo-500 hover:opacity-90 transition-opacity"
          >
            Sign In
          </Link>
        </div>
      </nav>

      {/* Main Content */}
      <main className="pt-32 pb-20 px-6">
        <div className="max-w-2xl mx-auto">
          {/* Back Link */}
          <Link
            href="/intro"
            className="inline-flex items-center gap-2 text-gray-600 hover:text-purple-600 transition-colors mb-8"
          >
            <ArrowLeft className="w-4 h-4" />
            Back to Home
          </Link>

          {/* Header */}
          <div className="text-center mb-12">
            <div className="w-16 h-16 mx-auto rounded-2xl bg-gradient-to-br from-pink-100 via-purple-100 to-indigo-100 flex items-center justify-center mb-6">
              <MessageCircle className="w-8 h-8 text-purple-600" />
            </div>
            <h1 className="text-4xl font-bold text-gray-900 mb-4">Contact Us</h1>
            <p className="text-lg text-gray-600">
              Have questions about CabinetScan? We&apos;re here to help.
            </p>
          </div>

          {/* Contact Options */}
          <div className="space-y-6">
            {/* Email Card */}
            <div className="p-6 rounded-2xl bg-gradient-to-br from-gray-50 to-white border border-gray-100">
              <div className="flex items-start gap-4">
                <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-pink-500 via-purple-500 to-indigo-500 flex items-center justify-center flex-shrink-0">
                  <Mail className="w-6 h-6 text-white" />
                </div>
                <div className="flex-1">
                  <h2 className="text-lg font-semibold text-gray-900 mb-1">Email Support</h2>
                  <p className="text-gray-600 mb-4">
                    Send us an email and we&apos;ll get back to you within 24 hours.
                  </p>
                  <a
                    href="mailto:contact@nextlyn.ai"
                    className="inline-flex items-center gap-2 px-6 py-3 text-base font-semibold text-white rounded-full bg-gradient-to-r from-pink-500 via-purple-500 to-indigo-500 hover:shadow-lg hover:shadow-purple-500/25 transition-all"
                  >
                    <Mail className="w-4 h-4" />
                    contact@nextlyn.ai
                  </a>
                </div>
              </div>
            </div>

            {/* Response Time Card */}
            <div className="p-6 rounded-2xl bg-gradient-to-br from-gray-50 to-white border border-gray-100">
              <div className="flex items-start gap-4">
                <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-indigo-500 to-purple-500 flex items-center justify-center flex-shrink-0">
                  <Clock className="w-6 h-6 text-white" />
                </div>
                <div className="flex-1">
                  <h2 className="text-lg font-semibold text-gray-900 mb-1">Response Time</h2>
                  <p className="text-gray-600">
                    We typically respond within 24 hours during business days. For urgent matters,
                    please include &quot;URGENT&quot; in your email subject line.
                  </p>
                </div>
              </div>
            </div>

            {/* Free Trial Card */}
            <div className="p-6 rounded-2xl bg-gradient-to-br from-gray-50 to-white border border-gray-100">
              <div className="flex items-start gap-4">
                <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-green-500 to-emerald-500 flex items-center justify-center flex-shrink-0">
                  <Sparkles className="w-6 h-6 text-white" />
                </div>
                <div className="flex-1">
                  <h2 className="text-lg font-semibold text-gray-900 mb-1">Start Your Free Trial</h2>
                  <p className="text-gray-600">
                    Interested in trying CabinetScan? Send us an email and let us know you&apos;d like to start
                    your 7-day free trial. We&apos;ll send you an invitation email soon to get you started.
                  </p>
                </div>
              </div>
            </div>
          </div>

          {/* FAQ Section */}
          <div className="mt-12">
            <h2 className="text-2xl font-bold text-gray-900 mb-6">Frequently Asked Questions</h2>
            <div className="space-y-4">
              <div className="p-5 rounded-xl bg-gray-50 border border-gray-100">
                <h3 className="font-semibold text-gray-900 mb-2">How do I get a Showroom Code?</h3>
                <p className="text-gray-600 text-sm">
                  Showroom codes are provided by cabinet showrooms to their customers. If you&apos;re a
                  showroom owner interested in CabinetScan, contact us to get started with your own code.
                </p>
              </div>
              <div className="p-5 rounded-xl bg-gray-50 border border-gray-100">
                <h3 className="font-semibold text-gray-900 mb-2">What devices support room scanning?</h3>
                <p className="text-gray-600 text-sm">
                  CabinetScan requires an iPhone or iPad with LiDAR scanner (iPhone 12 Pro and later,
                  iPad Pro 2020 and later) running iOS 17 or newer.
                </p>
              </div>
              <div className="p-5 rounded-xl bg-gray-50 border border-gray-100">
                <h3 className="font-semibold text-gray-900 mb-2">How accurate are the measurements?</h3>
                <p className="text-gray-600 text-sm">
                  Using Apple&apos;s LiDAR technology, CabinetScan provides room measurements within
                  ½ to ¾ inch accuracy, suitable for preliminary cabinet quotes.
                </p>
              </div>
              <div className="p-5 rounded-xl bg-gray-50 border border-gray-100">
                <h3 className="font-semibold text-gray-900 mb-2">I&apos;m a showroom owner. How do I sign up?</h3>
                <p className="text-gray-600 text-sm">
                  Contact us at contact@nextlyn.ai to learn about our plans and get started with a
                  free one-week trial. We&apos;ll set up your branded showroom experience.
                </p>
              </div>
            </div>
          </div>
        </div>
      </main>

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
