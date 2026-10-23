import ObjectiveC
import UIKit

/// Extensión "Compartir" de Video Downloader: toma el enlace (o el texto) que compartes desde
/// YouTube, Safari, WhatsApp… y abre la app con videodownloader://open?url=<enlace>.
///
/// iOS no deja a las extensiones abrir su app de forma oficial: se busca en la cadena de
/// "responders" quien sepa abrir enlaces y se le llama por el runtime de Objective-C (sin usar
/// UIApplication, que Xcode no permite en extensiones: APPLICATION_EXTENSION_API_ONLY = YES).
/// Si eso falla, el enlace se copia con una marca propia (caduca en 10 min) y la app ofrece
/// abrirlo al volver a ella.
final class ShareViewController: UIViewController {
  private static let scheme = "videodownloader"
  private static let clipboardMarker = "com.marcoyam.videodownloader.shared-link"
  private var started = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor.black.withAlphaComponent(0.01)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !started else { return }
    started = true
    sharedText { [weak self] text in
      DispatchQueue.main.async { self?.handle(text) }
    }
  }

  /// Primer enlace (public.url) o texto (public.plain-text) de lo compartido.
  private func sharedText(_ done: @escaping (String?) -> Void) {
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
    if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.url") }) {
      p.loadItem(forTypeIdentifier: "public.url", options: nil) { item, _ in
        done((item as? URL)?.absoluteString ?? (item as? String))
      }
      return
    }
    if let p = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.plain-text") }) {
      p.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { item, _ in
        done(item as? String)
      }
      return
    }
    done(nil)
  }

  private func handle(_ text: String?) {
    guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
      finish(message: "No encontré un enlace para abrir.")
      return
    }
    var components = URLComponents()
    components.scheme = Self.scheme
    components.host = "open"
    components.queryItems = [URLQueryItem(name: "url", value: text)]
    guard let url = components.url else {
      finish(message: "No encontré un enlace para abrir.")
      return
    }
    openHostApp(url) { [weak self] opened in
      DispatchQueue.main.async {
        if opened {
          self?.extensionContext?.completeRequest(returningItems: nil)
        } else {
          self?.copyForLater(text)
          self?.finish(message: "Copiado: abre Video Downloader para verlo.")
        }
      }
    }
  }

  /// Busca en la cadena de responders quien responda a openURL:options:completionHandler: (la
  /// aplicación) y lo llama por el runtime, sin nombrar UIApplication.
  private func openHostApp(_ url: URL, completion: @escaping (Bool) -> Void) {
    typealias OpenURL = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?) -> Void
    let selector = NSSelectorFromString("openURL:options:completionHandler:")
    var responder: UIResponder? = self
    while let current = responder {
      if current.responds(to: selector), let method = class_getInstanceMethod(type(of: current), selector) {
        let open = unsafeBitCast(method_getImplementation(method), to: OpenURL.self)
        let done: @convention(block) (Bool) -> Void = { completion($0) }
        open(current, selector, url as NSURL, NSDictionary(), done)
        return
      }
      responder = current.next
    }
    completion(false)
  }

  /// Copia el enlace con la marca que la app revisa (sin leer el portapapeles) al volver.
  private func copyForLater(_ text: String) {
    let item: [String: Any] = ["public.utf8-plain-text": text, Self.clipboardMarker: Data("1".utf8)]
    UIPasteboard.general.setItems([item], options: [.expirationDate: Date().addingTimeInterval(600)])
  }

  private func finish(message: String) {
    let alert = UIAlertController(title: "Video Downloader", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
      self?.extensionContext?.completeRequest(returningItems: nil)
    })
    present(alert, animated: true)
  }
}
