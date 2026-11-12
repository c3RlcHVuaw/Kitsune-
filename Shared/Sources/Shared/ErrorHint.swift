import Foundation

/// Turns the core's raw log lines into one plain sentence and a hint of what to do. nil when the line isn't recognised.
public enum ErrorHint {
    /// Checked in order, so the specific causes come before the generic timeout.
    private static let rules: [(needles: [String], text: String)] = [
        (["invalid public_key", "invalid short_id", "short id", "reality verification failed"], "Сервер сменил ключ. Обновите подписку."),
        (["authentication failed", "unauthorized", "invalid user", "invalid uuid", "wrong password"], "Сервер не принял ключ. Обновите подписку."),
        (["address already in use"], "Порт занят другой программой. Закройте её или смените порт раздачи."),
        (["x509", "certificate"], "Сервер предъявил неверный сертификат. Попробуйте другой сервер."),
        (["no such host", "lookup "], "Не удалось найти адрес сервера. Проверьте интернет или выберите другой."),
        (["network is unreachable", "no route to host"], "Нет подключения к интернету."),
        (["connection refused"], "Сервер отклонил подключение. Выберите другой."),
        (["i/o timeout", "context deadline exceeded", "timeout"], "Сервер не отвечает. Выберите другой."),
        (["handshake", "tls:"], "Не удалось установить защищённое соединение. Попробуйте другой сервер."),
    ]

    public static func explain(_ raw: String) -> String? {
        let line = raw.lowercased()
        return rules.first { $0.needles.contains(where: line.contains) }?.text
    }
}
