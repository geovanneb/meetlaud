package com.meetlaud.app.infra.archive

import com.meetlaud.domain.ArchiveError
import com.meetlaud.domain.ArchiveException
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.security.SecureRandom
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * The file format of SealedStream.swift, byte for byte, so a library moves between an iPhone and an Android phone:
 * a clear header (magic, iterations, salt, nonce base), then sealed blocks of 1 MB of plain text each.
 *
 * Each block's nonce comes from its position, and its position and "last block" flag are authenticated, so blocks
 * cannot be reordered, removed, or cut off the end without the read failing.
 */
internal object SealedFormat {
    val magic = "MEETLAUD-ARCHIVE-1\n".toByteArray(Charsets.UTF_8)
    const val BLOCK_SIZE = 1024 * 1024
    /** OWASP's figure for PBKDF2 with SHA-256. Slow on purpose: this is all that stands between a guess and a meeting. */
    const val ITERATIONS = 600_000
    const val SALT_SIZE = 16
    const val NONCE_SIZE = 12
    const val TAG_BITS = 128

    /** PBKDF2-HMAC-SHA256 over the password's UTF-8 bytes, as CommonCrypto does. Written out so no provider re-encodes the password. */
    fun key(password: String, salt: ByteArray, iterations: Int): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        val passwordBytes = password.toByteArray(Charsets.UTF_8)
        // The JCA refuses an empty key. HMAC pads every key with zeros to 64 bytes, so this is the same key.
        mac.init(SecretKeySpec(if (passwordBytes.isEmpty()) ByteArray(64) else passwordBytes, "HmacSHA256"))
        val block = ByteArray(32)
        val output = ByteArray(32)
        mac.update(salt)
        mac.update(byteArrayOf(0, 0, 0, 1))
        mac.doFinal(block, 0)
        block.copyInto(output)
        repeat(iterations - 1) {
            mac.update(block)
            mac.doFinal(block, 0)
            for (index in output.indices) output[index] = (output[index].toInt() xor block[index].toInt()).toByte()
        }
        return output
    }

    fun nonce(base: ByteArray, counter: Long): ByteArray {
        val bytes = base.copyOf()
        for (index in 0 until 8) {
            val position = bytes.size - 1 - index
            bytes[position] = (bytes[position].toInt() xor ((counter ushr (index * 8)) and 0xFF).toInt()).toByte()
        }
        return bytes
    }

    fun context(counter: Long, isLast: Boolean): ByteArray = longBytes(counter) + byteArrayOf(if (isLast) 1 else 0)

    fun intBytes(value: Int): ByteArray = ByteArray(4) { (value ushr (24 - it * 8)).toByte() }
    fun longBytes(value: Long): ByteArray = ByteArray(8) { (value ushr (56 - it * 8)).toByte() }
}

/** Writes plain bytes in, sealed blocks out. */
internal class SealedWriter(file: File, password: String, random: SecureRandom = SecureRandom()) {
    private val output: OutputStream = file.outputStream().buffered()
    private val key: SecretKeySpec
    private val base = ByteArray(SealedFormat.NONCE_SIZE).also(random::nextBytes)
    private var counter = 0L
    private val pending = java.io.ByteArrayOutputStream()

    init {
        val salt = ByteArray(SealedFormat.SALT_SIZE).also(random::nextBytes)
        key = SecretKeySpec(SealedFormat.key(password, salt, SealedFormat.ITERATIONS), "AES")
        output.write(SealedFormat.magic)
        output.write(SealedFormat.intBytes(SealedFormat.ITERATIONS))
        output.write(salt)
        output.write(base)
    }

    fun write(data: ByteArray, length: Int = data.size) {
        pending.write(data, 0, length)
        if (pending.size() > SealedFormat.BLOCK_SIZE) {
            val all = pending.toByteArray()
            pending.reset()
            var offset = 0
            while (all.size - offset > SealedFormat.BLOCK_SIZE) {
                seal(all.copyOfRange(offset, offset + SealedFormat.BLOCK_SIZE), isLast = false)
                offset += SealedFormat.BLOCK_SIZE
            }
            pending.write(all, offset, all.size - offset)
        }
    }

    fun finish() {
        seal(pending.toByteArray(), isLast = true)
        pending.reset()
        output.close()
    }

    fun abandon() = runCatching { output.close() }

    private fun seal(block: ByteArray, isLast: Boolean) {
        val nonce = SealedFormat.nonce(base, counter)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(SealedFormat.TAG_BITS, nonce))
        cipher.updateAAD(SealedFormat.context(counter, isLast))
        // CryptoKit's "combined" form: nonce, then cipher text, then tag. The JCA gives the last two together.
        val sealed = cipher.doFinal(block)
        output.write(if (isLast) 1 else 0)
        output.write(SealedFormat.intBytes(nonce.size + sealed.size))
        output.write(nonce)
        output.write(sealed)
        counter += 1
    }
}

/** Reads sealed blocks in, plain bytes out. Only ever hands over text that passed authentication. */
internal class SealedReader(file: File, password: String) : AutoCloseable {
    private val input: InputStream = file.inputStream().buffered()
    private val key: SecretKeySpec
    private val base: ByteArray
    private var counter = 0L
    private var pending = ByteArray(0)
    private var position = 0
    private var finished = false
    var bytesRead = 0L
        private set

    init {
        val header = readFully(SealedFormat.magic.size + 4 + SealedFormat.SALT_SIZE + SealedFormat.NONCE_SIZE)
        if (!header.copyOfRange(0, SealedFormat.magic.size).contentEquals(SealedFormat.magic)) damaged()
        var offset = SealedFormat.magic.size
        val iterations = header.copyOfRange(offset, offset + 4).fold(0L) { value, byte -> (value shl 8) or (byte.toLong() and 0xFF) }
        // A forged header must not be able to freeze the phone, or weaken the key to nothing.
        if (iterations !in 100_000L..10_000_000L) damaged()
        offset += 4
        val salt = header.copyOfRange(offset, offset + SealedFormat.SALT_SIZE)
        offset += SealedFormat.SALT_SIZE
        base = header.copyOfRange(offset, header.size)
        key = SecretKeySpec(SealedFormat.key(password, salt, iterations.toInt()), "AES")
    }

    override fun close() = input.close()

    /** Exactly `count` bytes, or an error. Running out early means the file was cut. */
    fun read(count: Int): ByteArray {
        while (pending.size - position < count) {
            if (!nextBlock()) damaged()
        }
        val result = pending.copyOfRange(position, position + count)
        position += count
        return result
    }

    /** The archive terminator is valid only at the authenticated end of the stream. */
    fun requireEnd() {
        if (pending.size != position) damaged()
        if (!finished) nextBlock()
        if (!finished || pending.size != position || input.read() != -1) damaged()
    }

    private fun nextBlock(): Boolean {
        if (finished) return false
        val head = readFully(5)
        if (head[0].toInt() !in 0..1) damaged()
        val isLast = head[0].toInt() == 1
        val size = head.copyOfRange(1, 5).fold(0L) { value, byte -> (value shl 8) or (byte.toLong() and 0xFF) }
        if (size > SealedFormat.BLOCK_SIZE + 64 || size < SealedFormat.NONCE_SIZE + 16) damaged()
        val body = readFully(size.toInt())
        val plain = try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(SealedFormat.TAG_BITS, body, 0, SealedFormat.NONCE_SIZE))
            cipher.updateAAD(SealedFormat.context(counter, isLast))
            cipher.doFinal(body, SealedFormat.NONCE_SIZE, body.size - SealedFormat.NONCE_SIZE)
        } catch (_: AEADBadTagException) {
            // On the very first block a failure almost always means a mistyped password.
            throw ArchiveException(if (counter == 0L) ArchiveError.WRONG_PASSWORD else ArchiveError.DAMAGED)
        } catch (_: Exception) {
            damaged()
        }
        pending = pending.copyOfRange(position, pending.size) + plain
        position = 0
        bytesRead += size + 5
        counter += 1
        finished = isLast
        return true
    }

    private fun readFully(count: Int): ByteArray {
        val bytes = ByteArray(count)
        var offset = 0
        while (offset < count) {
            val read = input.read(bytes, offset, count - offset)
            if (read < 0) damaged()
            offset += read
        }
        return bytes
    }

    private fun damaged(): Nothing = throw ArchiveException(ArchiveError.DAMAGED)
}

