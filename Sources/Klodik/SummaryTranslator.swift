import Foundation
import Translation
import KlodikCore

/// Итоги ходов Claude иногда пишет по-английски. Переводим их на язык интерфейса на самом Mac (Apple Translation,
/// без сети). Нужны macOS 26 и скачанные языки перевода (кнопка в настройках); без них строки остаются как есть.
final class SummaryTranslator {
    enum Status { case ready, needsDownload, unavailable }

    private(set) var status: Status = .unavailable
    /// Пришли переводы или поменялся статус — пора перерисовать. На главной очереди.
    var onChange: (() -> Void)?

    /// С какого языка переводим: с «другого» из двух языков интерфейса.
    let sourceLang: Lang = Lang.current == .ru ? .en : .ru
    var source: Locale.Language { Locale.Language(identifier: sourceLang == .en ? "en" : "ru") }
    var target: Locale.Language { Locale.Language(identifier: Lang.current == .ru ? "ru" : "en") }

    /// Строка → что показывать. Строки на нужном языке тоже здесь, чтобы не распознавать язык на каждом пересчёте.
    private var done: [String: String] = [:]
    private var queue: [String] = []
    private var running = false

    func checkStatus() {
        guard #available(macOS 26, *) else { return }
        Task { @MainActor in
            let status: Status = switch await LanguageAvailability().status(from: source, to: target) {
            case .installed: .ready
            case .supported: .needsDownload
            default: .unavailable
            }
            guard status != self.status else { return }
            self.status = status
            onChange?()
            run()
        }
    }

    /// Перевод, если он уже готов; иначе исходная строка, а перевод придёт через `onChange`.
    func text(_ original: String) -> String {
        if let known = done[original] { return known }
        guard TextLanguage.detect(original) == sourceLang else {
            done[original] = original
            return original
        }
        if !queue.contains(original) { queue.append(original) }
        run()
        return original
    }

    private func run() {
        guard #available(macOS 26, *), status == .ready, !running, !queue.isEmpty else { return }
        running = true
        let batch = queue
        queue = []
        Task { @MainActor in
            let session = TranslationSession(installedSource: source, target: target)
            for text in batch {
                // Не перевелось — показываем как есть и больше не пытаемся.
                done[text] = (try? await session.translate(text).targetText) ?? text
            }
            // Сессий немного, но за неделю итогов набирается много: старые просто забываем.
            if done.count > 1000 { done = done.filter { batch.contains($0.key) } }
            running = false
            onChange?()
            run()
        }
    }
}
