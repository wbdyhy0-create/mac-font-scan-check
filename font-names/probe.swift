// Opens a page in the system's web view and writes down what the page answers; before that, prints how the system itself names the
// test fonts.   probe <mode> <page.html> <answer.json> [folder of the test fonts]
import AppKit
import CoreText
import WebKit

let arguments = CommandLine.arguments
let mode = arguments[1]
let page = URL(fileURLWithPath: arguments[2])
let answerPath = arguments[3]

func isTest(_ family: String) -> Bool { family.hasPrefix("Probe") || family.hasPrefix("בדיקה") }

if arguments.count > 4 {
  let folder = arguments[4]
  print("== each test file, as the system reads it ==")
  let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasPrefix("Probe") }.sorted()
  for file in files {
    let url = URL(fileURLWithPath: folder).appendingPathComponent(file) as CFURL
    guard let found = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor] else {
      print("\(file)\tnot read")
      continue
    }
    for descriptor in found {
      let text = { (key: CFString) -> String in (CTFontDescriptorCopyAttribute(descriptor, key) as? String) ?? "-" }
      let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [CFString: Any]
      let weight = (traits?[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? Double.nan
      let symbolic = (traits?[kCTFontSymbolicTrait] as? NSNumber)?.uint32Value ?? 0
      print("\(file)\tfamily=\(text(kCTFontFamilyNameAttribute))\tstyle=\(text(kCTFontStyleNameAttribute))\tshort=\(text(kCTFontNameAttribute))\tshown=\(text(kCTFontDisplayNameAttribute))\tweight=\(String(format: "%.2f", weight))\tbold=\(symbolic & 2 != 0)")
    }
  }
  print("== the test families among the installed fonts, and their members (short name, style, weight 0-15, traits) ==")
  let manager = NSFontManager.shared
  for family in manager.availableFontFamilies where isTest(family) {
    for member in manager.availableMembers(ofFontFamily: family) ?? [] {
      print("\(family)\t\(member.map { "\($0)" }.joined(separator: "\t"))")
    }
  }
}

final class Listener: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
  func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    let text = (message.body as? String) ?? "{}"
    try? text.write(toFile: answerPath, atomically: true, encoding: .utf8)
    print("the page answered (\(text.count) characters)")
    exit(0)
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    print("the page failed: \(error)")
    exit(2)
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    print("the page failed to open: \(error)")
    exit(2)
  }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let listener = Listener()
let configuration = WKWebViewConfiguration()
configuration.userContentController.add(listener, name: "done")
let families = NSFontManager.shared.availableFontFamilies
let familiesJSON = String(data: try! JSONSerialization.data(withJSONObject: families), encoding: .utf8)!
configuration.userContentController.addUserScript(WKUserScript(source: "window.MODE = '\(mode)'; window.ALL_FAMILIES = \(familiesJSON);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
let frame = NSRect(x: 40, y: 40, width: 1200, height: 800)
let view = WKWebView(frame: frame, configuration: configuration)
view.navigationDelegate = listener
let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = view
window.orderFrontRegardless()
view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
DispatchQueue.main.asyncAfter(deadline: .now() + 240) {
  print("the page did not answer in four minutes")
  exit(3)
}
app.run()
