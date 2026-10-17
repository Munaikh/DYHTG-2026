import AlgorithmArenaCore
import Foundation
import Supabase

enum ArenaBackend {
    static let url = URL(string: "https://gftmvsmamkpvqrvbhoze.supabase.co")!
    static let publishableKey = "sb_publishable_9oQ9naBHWHur6bKzVwju2Q_4Kwe06Sf"

    static let client = SupabaseClient(
        supabaseURL: url,
        supabaseKey: publishableKey,
        options: SupabaseClientOptions(
            db: .init(encoder: ContractJSON.encoder(), decoder: ContractJSON.decoder())
        )
    )
}
