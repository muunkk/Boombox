import Combine
import Testing
@testable import Kaset

@MainActor
struct CheckForUpdatesViewModelTests {
    @Test
    func tracksPublisherValues() {
        let subject = CurrentValueSubject<Bool, Never>(false)
        let viewModel = CheckForUpdatesViewModel(canCheckPublisher: subject.eraseToAnyPublisher())

        #expect(viewModel.canCheckForUpdates == false)

        subject.send(true)
        #expect(viewModel.canCheckForUpdates == true)

        subject.send(false)
        #expect(viewModel.canCheckForUpdates == false)
    }
}
