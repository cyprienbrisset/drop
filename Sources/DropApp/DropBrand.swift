import SwiftUI

/// Identité visuelle du produit — la même que la page GitHub Pages (le corbeau, l'aile irisée) :
/// une seule couleur de marque plutôt que le bleu système par défaut, appliquée comme teinte sur
/// chaque fenêtre pour que les boutons/cases/liens la portent sans avoir à la répéter partout.
/// Volontairement fixe (pas dérivée de `accentColor` système) : c'est ce fil visuel constant, pas
/// le réglage d'apparence de la machine, qui donne à l'app un visage reconnaissable — la même
/// logique que l'icône bleu-vert de CleanMyMac ou le vert sépia de Family Tree.
extension Color {
    static let dropBrand = Color(red: 0.204, green: 0.518, blue: 0.482)
}
