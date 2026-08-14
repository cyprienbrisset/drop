import DropCore
import DropVault
import Foundation
import Testing

@Test func vaultServiceInitializesWithGivenRoot() {
    let root = URL(fileURLWithPath: "/tmp/drop-vault-test")
    _ = VaultService(vaultRoot: root, fileSystem: LiveFileSystem(), clock: SystemClock())
}
