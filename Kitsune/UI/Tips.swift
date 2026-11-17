import SwiftUI
import TipKit

// One-time hints shown in place, the first time each feature is in view. TipKit remembers what was dismissed.

struct ServerActionsTip: Tip {
    var title: Text { Text("Действия с сервером") }
    var message: Text? { Text("Правый клик по серверу: закрепить, проверить пинг или сделать входным для двойного прыжка. Нажатие на флаг переворачивает карточку, а сортировка «По стране» собирает серверы в группы.") }
    var image: Image? { Image(systemName: "cursorarrow.click.2") }
}

struct AppRulesTip: Tip {
    var title: Text { Text("Правило для приложения") }
    var message: Text? { Text("Правый клик по приложению отправит его напрямую или через VPN.") }
    var image: Image? { Image(systemName: "app.badge") }
}
