import Foundation

/// Vecteur quantifié int8 avec son échelle (§5.5). 100 000 chunks en float32 pèsent ≈ 2 Go ; en
/// int8 sur disque avec `mmap`, l'empreinte résidente tombe à ~40–80 Mo — c'est la différence
/// entre une application utilisable et une application qui fait paginer la machine.
public struct QuantizedVector: Sendable, Equatable {
    public let values: [Int8]
    public let scale: Double

    public init(values: [Int8], scale: Double) {
        self.values = values
        self.scale = scale
    }
}

/// Quantification linéaire symétrique, échelle par vecteur (§5.5) : `scale = max(|v|) / 127`,
/// `quantized[i] = round(v[i] / scale)`, borné à [-127, 127].
public enum EmbeddingQuantizer {
    public static func quantize(_ vector: [Double]) -> QuantizedVector {
        let maxAbs = vector.map(abs).max() ?? 0
        guard maxAbs > 0 else {
            return QuantizedVector(values: [Int8](repeating: 0, count: vector.count), scale: 1.0)
        }

        let scale = maxAbs / 127.0
        let values = vector.map { value -> Int8 in
            let scaled = (value / scale).rounded()
            return Int8(max(-127, min(127, scaled)))
        }
        return QuantizedVector(values: values, scale: scale)
    }

    public static func dequantize(_ quantized: QuantizedVector) -> [Double] {
        quantized.values.map { Double($0) * quantized.scale }
    }
}
