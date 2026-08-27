import Observation
import ServiceManagement

protocol LoginItemServicing: AnyObject {
    var status: SMAppService.Status { get }

    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemServicing {}

@MainActor
@Observable
final class LaunchAtLoginController {
    @ObservationIgnored private let service: any LoginItemServicing

    private(set) var status: SMAppService.Status
    private(set) var errorMessage: String?

    init(service: any LoginItemServicing = SMAppService.mainApp) {
        self.service = service
        status = service.status
    }

    var isRequested: Bool {
        status == .enabled || status == .requiresApproval
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    var isAvailable: Bool {
        status != .notFound
    }

    func setEnabled(_ shouldEnable: Bool) {
        errorMessage = nil

        do {
            if shouldEnable {
                switch service.status {
                case .notRegistered:
                    try service.register()
                case .enabled, .requiresApproval:
                    break
                case .notFound:
                    errorMessage = "Launch at Login is unavailable for this build"
                @unknown default:
                    errorMessage = "Launch at Login returned an unknown status"
                }
            } else {
                switch service.status {
                case .enabled, .requiresApproval:
                    try service.unregister()
                case .notRegistered, .notFound:
                    break
                @unknown default:
                    errorMessage = "Launch at Login returned an unknown status"
                }
            }
        } catch {
            errorMessage = "Could not update Launch at Login: \(error.localizedDescription)"
        }

        refresh()
    }

    func refresh() {
        status = service.status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
