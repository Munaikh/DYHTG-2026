import MapKit
import Observation
import SwiftUI

@MainActor @Observable
private final class PlaceSuggestions: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
    var query = "" { didSet { completer.queryFragment=query } }
    var results: [MKLocalSearchCompletion] = []
    var error: String?
    private let completer=MKLocalSearchCompleter()
    override init() { super.init();completer.delegate=self;completer.resultTypes=[.address,.pointOfInterest] }
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results=completer.results;error=nil
    }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        self.error="Place search is unavailable. Please try again."
    }
}
struct PlaceSearchView: View {
    let title: String
    let select: (MKMapItem) -> Void
    @State private var suggestions=PlaceSuggestions()
    @State private var loading=false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView("Finding place…") }
                if let message=error ?? suggestions.error { Text(message).foregroundStyle(.red) }
                ForEach(Array(suggestions.results.enumerated()),id:\.offset) { _,result in
                    Button {
                        loading=true
                        Task {
                            defer { loading=false }
                            do {
                                let response=try await MKLocalSearch(request:MKLocalSearch.Request(completion:result)).start()
                                guard let item=response.mapItems.first else { return }
                                select(item);dismiss()
                            } catch { self.error="Could not find this place. Try another search." }
                        }
                    } label: {
                        VStack(alignment:.leading) { Text(result.title);Text(result.subtitle).font(.caption).foregroundStyle(.secondary) }
                    }.disabled(loading)
                }
                if suggestions.query.isEmpty { Text("Search streets, addresses, universities, parks or landmarks.").foregroundStyle(.secondary) }
            }
            .searchable(text:$suggestions.query,prompt:"Where would you like to go?")
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
