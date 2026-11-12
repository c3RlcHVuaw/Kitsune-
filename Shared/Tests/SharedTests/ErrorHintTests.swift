import Testing
@testable import Shared

@Test func rawCoreErrorsBecomeSentences() {
    #expect(ErrorHint.explain("FATAL initialize outbound[0]: invalid public_key") == "Сервер сменил ключ. Обновите подписку.")
    #expect(ErrorHint.explain("ERROR dial tcp 1.2.3.4:443: i/o timeout") == "Сервер не отвечает. Выберите другой.")
    #expect(ErrorHint.explain("listen tcp 0.0.0.0:7890: bind: address already in use") == "Порт занят другой программой. Закройте её или смените порт раздачи.")
    #expect(ErrorHint.explain("something nobody has seen") == nil)
}
