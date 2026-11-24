package com.kitsune.vpn.core

import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

/** Plain Map/List/String/Number/Boolean trees: what sing-box configs and outbounds are made of. */
@Suppress("UNCHECKED_CAST")
object Json {
    fun parse(text: String): Any? = try { unwrap(JSONTokener(text).nextValue()) } catch (_: Exception) { null }

    fun obj(text: String): Map<String, Any?>? = parse(text) as? Map<String, Any?>

    private fun unwrap(value: Any?): Any? = when (value) {
        is JSONObject -> value.keys().asSequence().associateWith { unwrap(value.get(it)) }
        is JSONArray -> List(value.length()) { unwrap(value.get(it)) }
        JSONObject.NULL -> null
        else -> value
    }

    /** Sorted keys and unescaped slashes, so the same outbound always produces the same text (and the same server id). */
    fun write(value: Any?, pretty: Boolean = false): String = StringBuilder().also { write(it, value, pretty, 0) }.toString()

    private fun write(out: StringBuilder, value: Any?, pretty: Boolean, depth: Int) {
        val pad = { n: Int -> if (pretty) "\n" + "  ".repeat(n) else "" }
        when (value) {
            null -> out.append("null")
            is String -> quote(out, value)
            is Boolean, is Int, is Long -> out.append(value)
            is Double -> out.append(if (value % 1.0 == 0.0 && kotlin.math.abs(value) < 1e15) value.toLong().toString() else value.toString())
            is Map<*, *> -> {
                if (value.isEmpty()) { out.append("{}"); return }
                out.append('{')
                value.entries.sortedBy { it.key.toString() }.forEachIndexed { i, e ->
                    if (i > 0) out.append(',')
                    out.append(pad(depth + 1)); quote(out, e.key.toString()); out.append(if (pretty) ": " else ":")
                    write(out, e.value, pretty, depth + 1)
                }
                out.append(pad(depth)).append('}')
            }
            is Collection<*> -> {
                if (value.isEmpty()) { out.append("[]"); return }
                out.append('[')
                value.forEachIndexed { i, item ->
                    if (i > 0) out.append(',')
                    out.append(pad(depth + 1)); write(out, item, pretty, depth + 1)
                }
                out.append(pad(depth)).append(']')
            }
            else -> quote(out, value.toString())
        }
    }

    private fun quote(out: StringBuilder, text: String) {
        out.append('"')
        for (c in text) when {
            c == '"' -> out.append("\\\"")
            c == '\\' -> out.append("\\\\")
            c == '\n' -> out.append("\\n")
            c == '\r' -> out.append("\\r")
            c == '\t' -> out.append("\\t")
            c < ' ' -> out.append("\\u%04x".format(c.code))
            else -> out.append(c)
        }
        out.append('"')
    }
}
