package com.donghan.molapp

import android.graphics.Bitmap
import java.io.ByteArrayOutputStream

/**
 * Minimal single-frame GIF89a encoder. The viewport is a still raster, so one frame matches the iOS
 * single-frame GIF export (File ▸ Export Display ▸ GIF). Android has no built-in GIF writer.
 *
 * ponytail: fixed 216-color web-safe palette — a known ceiling (banding vs. iOS's adaptive palette).
 * Upgrade to an adaptive quantizer (NeuQuant/median-cut) only if GIF quality is ever a requirement.
 * The LZW stage is the classic `compress`-based encoder (Kevin Weiner port), which is well tested,
 * so the risky bit-packing/variable-width logic is a known-good quantity.
 */
object GifEncoder {

    private val webSafeLevels = intArrayOf(0, 51, 102, 153, 204, 255)

    fun encode(bmp: Bitmap): ByteArray {
        val w = bmp.width
        val h = bmp.height
        val px = IntArray(w * h)
        bmp.getPixels(px, 0, w, 0, 0, w, h)

        // Map every pixel to a web-safe palette index (6 levels/channel → 216 colors).
        val indexed = ByteArray(w * h)
        for (i in px.indices) {
            val c = px[i]
            val ri = ((c ushr 16 and 0xFF) * 5 + 127) / 255
            val gi = ((c ushr 8 and 0xFF) * 5 + 127) / 255
            val bi = ((c and 0xFF) * 5 + 127) / 255
            indexed[i] = (ri * 36 + gi * 6 + bi).toByte()
        }

        val out = ByteArrayOutputStream()
        out.write("GIF89a".toByteArray(Charsets.US_ASCII))
        // Logical Screen Descriptor.
        writeShort(out, w); writeShort(out, h)
        out.write(0xF7)   // global color table present, 8-bit, 256 entries
        out.write(0)      // background color index
        out.write(0)      // pixel aspect ratio
        // Global color table: 216 web-safe colors, padded to 256.
        for (r in 0 until 6) for (g in 0 until 6) for (b in 0 until 6) {
            out.write(webSafeLevels[r]); out.write(webSafeLevels[g]); out.write(webSafeLevels[b])
        }
        repeat(256 - 216) { out.write(0); out.write(0); out.write(0) }
        // Image Descriptor.
        out.write(0x2C)
        writeShort(out, 0); writeShort(out, 0)
        writeShort(out, w); writeShort(out, h)
        out.write(0)      // no local color table, not interlaced
        // LZW-compressed image data (8-bit indices → min code size 8).
        LZW(indexed, 8, out).encode()
        out.write(0x3B)   // trailer
        return out.toByteArray()
    }

    private fun writeShort(out: ByteArrayOutputStream, v: Int) {
        out.write(v and 0xFF); out.write((v ushr 8) and 0xFF)
    }

    /** Classic variable-width LZW GIF compressor (compress-derived), driven by an index array. */
    private class LZW(private val pixels: ByteArray, private val initCodeSize: Int, private val out: ByteArrayOutputStream) {
        private val BITS = 12
        private val HSIZE = 5003
        private val maxMaxCode = 1 shl BITS
        private val masks = intArrayOf(
            0x0000, 0x0001, 0x0003, 0x0007, 0x000F, 0x001F, 0x003F, 0x007F, 0x00FF,
            0x01FF, 0x03FF, 0x07FF, 0x0FFF, 0x1FFF, 0x3FFF, 0x7FFF, 0xFFFF
        )
        private val htab = IntArray(HSIZE)
        private val codetab = IntArray(HSIZE)

        private var nBits = 0
        private var maxCode = 0
        private var freeEnt = 0
        private var clearFlag = false
        private var gInitBits = 0
        private var clearCode = 0
        private var eofCode = 0
        private var curAccum = 0
        private var curBits = 0
        private var aCount = 0
        private val accum = ByteArray(256)
        private var curPixel = 0

        fun encode() {
            out.write(initCodeSize)      // min LZW code size
            compress(initCodeSize + 1)
            out.write(0)                 // block terminator
        }

        private fun maxcode(n: Int) = (1 shl n) - 1

        private fun nextPixel(): Int {
            if (curPixel >= pixels.size) return -1
            return pixels[curPixel++].toInt() and 0xFF
        }

        private fun compress(initBits: Int) {
            gInitBits = initBits
            clearFlag = false
            nBits = gInitBits
            maxCode = maxcode(nBits)
            clearCode = 1 shl (initBits - 1)
            eofCode = clearCode + 1
            freeEnt = clearCode + 2
            aCount = 0

            var ent = nextPixel()
            var hshift = 0
            var fcode = HSIZE
            while (fcode < 65536) { hshift++; fcode *= 2 }
            hshift = 8 - hshift
            resetHash()
            output(clearCode)

            var c = nextPixel()
            outer@ while (c != -1) {
                fcode = (c shl BITS) + ent
                var i = (c shl hshift) xor ent
                if (htab[i] == fcode) {
                    ent = codetab[i]; c = nextPixel(); continue
                } else if (htab[i] >= 0) {
                    var disp = HSIZE - i
                    if (i == 0) disp = 1
                    do {
                        i -= disp
                        if (i < 0) i += HSIZE
                        if (htab[i] == fcode) { ent = codetab[i]; c = nextPixel(); continue@outer }
                    } while (htab[i] >= 0)
                }
                output(ent)
                ent = c
                if (freeEnt < maxMaxCode) {
                    codetab[i] = freeEnt++
                    htab[i] = fcode
                } else {
                    resetBlock()
                }
                c = nextPixel()
            }
            output(ent)
            output(eofCode)
        }

        private fun output(code: Int) {
            curAccum = curAccum and masks[curBits]
            curAccum = if (curBits > 0) curAccum or (code shl curBits) else code
            curBits += nBits
            while (curBits >= 8) { charOut((curAccum and 0xFF).toByte()); curAccum = curAccum ushr 8; curBits -= 8 }

            if (freeEnt > maxCode || clearFlag) {
                if (clearFlag) { nBits = gInitBits; maxCode = maxcode(nBits); clearFlag = false }
                else { nBits++; maxCode = if (nBits == BITS) maxMaxCode else maxcode(nBits) }
            }
            if (code == eofCode) {
                while (curBits > 0) { charOut((curAccum and 0xFF).toByte()); curAccum = curAccum ushr 8; curBits -= 8 }
                flushBlock()
            }
        }

        private fun resetBlock() {
            resetHash()
            freeEnt = clearCode + 2
            clearFlag = true
            output(clearCode)
        }

        private fun resetHash() { for (i in 0 until HSIZE) htab[i] = -1 }

        private fun charOut(b: Byte) {
            accum[aCount++] = b
            if (aCount >= 254) flushBlock()
        }

        private fun flushBlock() {
            if (aCount > 0) { out.write(aCount); out.write(accum, 0, aCount); aCount = 0 }
        }
    }
}
