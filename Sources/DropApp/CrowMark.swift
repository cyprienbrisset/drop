import SwiftUI

/// La marque du produit (§identité visuelle, cohérente avec la page GitHub Pages) : un corbeau
/// perché, l'aile irisée — jamais un simple symbole SF générique là où l'app a vraiment quelque
/// chose à dire d'elle-même (écran d'accueil, états vides). Dessiné en SwiftUI plutôt que bundlé
/// en image : ce paquet Swift n'a pas de catalogue d'assets, et une seule source de vérité pour
/// cette silhouette évite qu'elle diverge d'un endroit à l'autre de l'app.
struct CrowMark: View {
    var size: CGFloat = 64
    /// Perché sur une branche avec pattes visibles pour les grandes tailles (accueil, états
    /// vides) ; pur buste pour les petites (là où la branche ne serait plus qu'un bruit de
    /// pixels indistinct).
    var showsPerch: Bool = true

    var body: some View {
        Canvas { context, canvasSize in
            let boxWidth: CGFloat = 260
            let boxHeight: CGFloat = 220
            let scale = min(canvasSize.width / boxWidth, canvasSize.height / boxHeight)
            context.translateBy(x: (canvasSize.width - boxWidth * scale) / 2, y: (canvasSize.height - boxHeight * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            // Le viewBox d'origine partait de x = -10 ; ce décalage recentre sur une origine 0.
            context.translateBy(x: 10, y: 0)

            let inkDark = Color(red: 0.043, green: 0.039, blue: 0.063)
            let inkMid = Color(red: 0.075, green: 0.071, blue: 0.098)

            if showsPerch {
                var branch = Path()
                branch.move(to: CGPoint(x: 45, y: 207)); branch.addLine(to: CGPoint(x: 205, y: 207))
                context.stroke(branch, with: .color(.secondary.opacity(0.4)), lineWidth: 3)

                var legs = Path()
                legs.move(to: CGPoint(x: 113, y: 182)); legs.addLine(to: CGPoint(x: 108, y: 206))
                legs.move(to: CGPoint(x: 141, y: 186)); legs.addLine(to: CGPoint(x: 149, y: 208))
                legs.move(to: CGPoint(x: 108, y: 206)); legs.addLine(to: CGPoint(x: 98, y: 210))
                legs.move(to: CGPoint(x: 108, y: 206)); legs.addLine(to: CGPoint(x: 119, y: 210))
                legs.move(to: CGPoint(x: 149, y: 208)); legs.addLine(to: CGPoint(x: 139, y: 212))
                legs.move(to: CGPoint(x: 149, y: 208)); legs.addLine(to: CGPoint(x: 160, y: 212))
                context.stroke(legs, with: .color(inkDark), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            }

            var tail = Path()
            tail.move(to: CGPoint(x: 188, y: 130)); tail.addLine(to: CGPoint(x: 231, y: 101)); tail.addLine(to: CGPoint(x: 199, y: 147)); tail.closeSubpath()
            context.fill(tail, with: .color(inkDark))
            var tail2 = Path()
            tail2.move(to: CGPoint(x: 192, y: 145)); tail2.addLine(to: CGPoint(x: 236, y: 133)); tail2.addLine(to: CGPoint(x: 201, y: 160)); tail2.closeSubpath()
            context.fill(tail2, with: .color(inkMid))
            var tail3 = Path()
            tail3.move(to: CGPoint(x: 188, y: 158)); tail3.addLine(to: CGPoint(x: 227, y: 169)); tail3.addLine(to: CGPoint(x: 197, y: 173)); tail3.closeSubpath()
            context.fill(tail3, with: .color(inkDark))

            var body = Path()
            body.move(to: CGPoint(x: 70, y: 150))
            body.addCurve(to: CGPoint(x: 115, y: 90), control1: CGPoint(x: 70, y: 120), control2: CGPoint(x: 85, y: 95))
            body.addCurve(to: CGPoint(x: 205, y: 130), control1: CGPoint(x: 150, y: 84), control2: CGPoint(x: 185, y: 100))
            body.addCurve(to: CGPoint(x: 195, y: 178), control1: CGPoint(x: 215, y: 145), control2: CGPoint(x: 210, y: 165))
            body.addCurve(to: CGPoint(x: 120, y: 190), control1: CGPoint(x: 175, y: 195), control2: CGPoint(x: 145, y: 198))
            body.addCurve(to: CGPoint(x: 70, y: 150), control1: CGPoint(x: 95, y: 182), control2: CGPoint(x: 70, y: 175))
            body.closeSubpath()
            context.fill(body, with: .linearGradient(
                Gradient(colors: [Color(red: 0.137, green: 0.125, blue: 0.188), inkDark]),
                startPoint: CGPoint(x: 60, y: 80), endPoint: CGPoint(x: 210, y: 190)
            ))

            var wing = Path()
            wing.move(to: CGPoint(x: 100, y: 96))
            wing.addCurve(to: CGPoint(x: 185, y: 105), control1: CGPoint(x: 125, y: 84), control2: CGPoint(x: 160, y: 86))
            wing.addCurve(to: CGPoint(x: 195, y: 142), control1: CGPoint(x: 200, y: 117), control2: CGPoint(x: 202, y: 130))
            wing.addCurve(to: CGPoint(x: 140, y: 148), control1: CGPoint(x: 185, y: 155), control2: CGPoint(x: 160, y: 152))
            wing.addCurve(to: CGPoint(x: 158, y: 116), control1: CGPoint(x: 155, y: 140), control2: CGPoint(x: 165, y: 128))
            wing.addCurve(to: CGPoint(x: 100, y: 96), control1: CGPoint(x: 148, y: 102), control2: CGPoint(x: 122, y: 98))
            wing.closeSubpath()
            context.fill(wing, with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.086, green: 0.780, blue: 0.690), Color(red: 0.541, green: 0.420, blue: 1.0),
                    Color(red: 1.0, green: 0.482, blue: 0.329),
                ]),
                startPoint: CGPoint(x: 90, y: 90), endPoint: CGPoint(x: 205, y: 180)
            ), style: FillStyle())

            let head = Path(ellipseIn: CGRect(x: 58 - 27, y: 82 - 27, width: 54, height: 54))
            context.fill(head, with: .color(inkMid))

            var beak = Path()
            beak.move(to: CGPoint(x: 30, y: 72)); beak.addLine(to: CGPoint(x: -6, y: 82)); beak.addLine(to: CGPoint(x: 30, y: 92)); beak.closeSubpath()
            context.fill(beak, with: .color(inkMid))

            context.fill(Path(ellipseIn: CGRect(x: 49 - 4.2, y: 75 - 4.2, width: 8.4, height: 8.4)), with: .color(Color(red: 0.906, green: 0.878, blue: 0.820)))
            context.fill(Path(ellipseIn: CGRect(x: 49 - 1.5, y: 75 - 1.5, width: 3, height: 3)), with: .color(inkDark))
        }
        .frame(width: size, height: size * (220.0 / 260.0))
    }
}

#Preview {
    VStack(spacing: 20) {
        CrowMark(size: 160)
        CrowMark(size: 48, showsPerch: false)
    }
    .padding(40)
}
