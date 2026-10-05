import Foundation

struct ToastNotification: Identifiable {
    let id = UUID()
    let message: String
    var detail: String? = nil
    var isError = false
    var duration: Duration = .seconds(2)
}
