import DropEmbeddings
import Testing

@Test func quantizingAndDequantizingStaysCloseToTheOriginalVector() {
    let original = [0.5, -0.2, 0.9, -1.0, 0.0]
    let quantized = EmbeddingQuantizer.quantize(original)
    let restored = EmbeddingQuantizer.dequantize(quantized)

    #expect(quantized.values.count == original.count)
    for (a, b) in zip(original, restored) {
        #expect(abs(a - b) < 0.02) // tolérance attendue de la quantification 8 bits.
    }
}

@Test func quantizedValuesStayWithinInt8Bounds() {
    let original = (0..<512).map { _ in Double.random(in: -5...5) }
    let quantized = EmbeddingQuantizer.quantize(original)
    for value in quantized.values {
        #expect(value >= -127 && value <= 127)
    }
}

@Test func quantizingAnAllZeroVectorDoesNotDivideByZero() {
    let quantized = EmbeddingQuantizer.quantize([0, 0, 0])
    #expect(quantized.values == [0, 0, 0])
    #expect(EmbeddingQuantizer.dequantize(quantized) == [0, 0, 0])
}

@Test func scaleReflectsTheLargestMagnitudeComponent() {
    let quantized = EmbeddingQuantizer.quantize([1.0, -4.0, 2.0])
    #expect(abs(quantized.scale - 4.0 / 127.0) < 1e-9)
}
