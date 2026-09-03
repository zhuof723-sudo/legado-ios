import SwiftUI

private struct ReaderActivePreferenceKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    func readerActive(_ active: Bool = true) -> some View {
        preference(key: ReaderActivePreferenceKey.self, value: active)
    }
}
