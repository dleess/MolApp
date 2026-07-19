package com.donghan.molapp

import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.WebView
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONObject
import java.util.UUID

/**
 * Kotlin counterpart of the iOS MolStarBridge: sends JSON command envelopes into the viewer
 * (window.molapp.handleNativeCommand) and receives events back over the MolAppAndroid
 * @JavascriptInterface. Owns the Compose-observable viewer state the UI renders.
 */
class MolStarBridge {
    private var webView: WebView? = null
    private val main = Handler(Looper.getMainLooper())
    private val pending = mutableListOf<String>()
    private var ready = false
    private var fatal = false

    // Optimistic-status helpers so a success result can name what completed.
    private var lastPdbName: String = ""
    private var lastRepresentationTitle: String = "Ribbon"

    // Compose-observable state.
    val objects = mutableStateListOf<MolAppObject>()
    val featureVisibility = mutableStateMapOf<String, Boolean>()
    var status by mutableStateOf("Ready for structure loading")
        private set
    var error by mutableStateOf<String?>(null)
        private set
    var measureKind by mutableStateOf<MeasureKind?>(null)
        private set
    var isMorphing by mutableStateOf(false)
        private set

    fun attach(webView: WebView) {
        this.webView = webView
        ready = false
        fatal = false
    }

    fun updateStatus(message: String) { status = message }
    fun updateError(message: String?) { error = message }
    fun clearError() { error = null }

    val visibleStructureNames: List<String>
        get() = objects.filter { it.type == "structure" && it.isVisible }.map { it.name }

    // ---- Command senders ------------------------------------------------------------------------

    fun loadLocalStructure(data: String, format: String, label: String?) {
        lastPdbName = label ?: "Structure"
        send("loadLocalStructure", JSONObject().apply {
            put("data", data); put("format", format); put("label", label ?: JSONObject.NULL)
        })
    }

    fun loadPdbId(pdbId: String) {
        lastPdbName = pdbId
        send("loadPdbId", JSONObject().put("pdbId", pdbId))
    }

    fun setRepresentation(representation: MoleculeRepresentation, targets: List<String>) {
        lastRepresentationTitle = representation.title
        send("setRepresentation", JSONObject().apply {
            put("representation", representation.raw); put("targets", targets.toJsonArray())
        })
    }

    fun toggleVisibility(feature: String, isVisible: Boolean) {
        send("toggleVisibility", JSONObject().apply { put("feature", feature); put("isVisible", isVisible) })
    }

    fun focusSelection() = send("focusSelection", JSONObject())

    fun setSelection(type: String, label: String?, ast: SelAst?) {
        send("setSelection", JSONObject().apply {
            put("type", type)
            label?.let { put("label", it) }
            ast?.let { put("ast", it.toJson()) }
        })
    }

    fun clearSelection() = send("clearSelection", JSONObject())

    fun setObjectVisibility(name: String, isVisible: Boolean) {
        send("setObjectVisibility", JSONObject().apply { put("name", name); put("isVisible", isVisible) })
    }

    fun setObjectRepresentation(name: String, representation: ObjectRepresentation) {
        send("setObjectRepresentation", JSONObject().apply { put("name", name); put("representation", representation.raw) })
    }

    fun setObjectColor(name: String, colorHex: String?) {
        send("setObjectColor", JSONObject().apply { put("name", name); put("colorHex", colorHex ?: JSONObject.NULL) })
    }

    fun drawSurfacePotential(targets: List<String>) =
        send("surfacePotential", JSONObject().put("targets", targets.toJsonArray()))

    fun startMorph(loop: Boolean, targets: List<String>) {
        send("startMorph", JSONObject().apply { put("durationInS", 5.0); put("loop", loop); put("targets", targets.toJsonArray()) })
    }

    fun stopMorph() = send("stopMorph", JSONObject())

    fun superpose(targets: List<String>) =
        send("superpose", JSONObject().put("targets", targets.toJsonArray()))

    fun computeSecondaryStructure(targets: List<String>) =
        send("secondaryStructure", JSONObject().put("targets", targets.toJsonArray()))

    fun setMeasureMode(enabled: Boolean, kind: String?) {
        // Track intent locally so the measurement banner/label reflects the active kind immediately.
        measureKind = if (enabled) MeasureKind.entries.firstOrNull { it.raw == kind } else null
        send("setMeasureMode", JSONObject().apply { put("enabled", enabled); kind?.let { put("kind", it) } })
    }

    fun clearMeasurements() = send("clearMeasurements", JSONObject())
    fun resetAll() = send("resetAll", JSONObject())
    fun undo() = send("undo", JSONObject())
    fun redo() = send("redo", JSONObject())

    private fun send(command: String, payload: JSONObject) {
        val envelope = JSONObject().apply {
            put("id", UUID.randomUUID().toString())
            put("command", command)
            put("payload", payload)
        }
        enqueue("window.molapp.handleNativeCommand($envelope); void 0;")
    }

    private fun enqueue(script: String) {
        if (fatal) return
        pending.add(script)
        flush()
    }

    private fun flush() {
        if (!ready) return
        val wv = webView ?: return
        val scripts = pending.toList()
        pending.clear()
        for (s in scripts) wv.evaluateJavascript(s, null)
    }

    // ---- Event receiver (called from the JS thread) ---------------------------------------------

    @JavascriptInterface
    fun postMessage(json: String) {
        val body = runCatching { JSONObject(json) }.getOrNull() ?: return
        main.post { receive(body) }
    }

    private fun receive(body: JSONObject) {
        when (body.optString("event")) {
            "viewerReady" -> { ready = true; error = null; flush(); return }
            "viewerError" -> {
                if (body.optBoolean("fatal")) { ready = false; fatal = true; pending.clear() }
                error = body.optString("message", "Mol* viewer error.")
                return
            }
            "selectionChanged", "pencilHover" -> return  // no-op on Android (no Pencil UI)
            "measurement" -> {
                val label = body.optString("label", null)
                if (label != null) {
                    status = "${measureKind?.title ?: "Distance"}: $label"
                }
                return
            }
            "objectsAdded" -> {
                val arr = body.optJSONArray("objects") ?: return
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    val name = o.optString("name", null) ?: continue
                    val rep = ObjectRepresentation.fromRaw(o.optString("representation")) ?: ObjectRepresentation.BALL_AND_STICK
                    addObject(MolAppObject(name = name, type = "selection", isVisible = true, representation = rep))
                }
                return
            }
            "objectsVisibility" -> {
                val arr = body.optJSONArray("items") ?: return
                for (i in 0 until arr.length()) {
                    val it = arr.optJSONObject(i) ?: continue
                    val name = it.optString("name", null) ?: continue
                    updateObject(name) { it2 -> it2.copy(isVisible = it.optBoolean("isVisible", true)) }
                }
                return
            }
            "featureVisibility" -> {
                val feature = body.optString("feature", null) ?: return
                featureVisibility[feature] = body.optBoolean("isVisible", true)
                return
            }
            "objectsReplaced" -> {
                val arr = body.optJSONArray("objects") ?: return
                val rebuilt = ArrayList<MolAppObject>()
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    val name = o.optString("name", null) ?: continue
                    val type = o.optString("type", null) ?: continue
                    val rep = ObjectRepresentation.fromRaw(o.optString("representation"))
                        ?: if (type == "structure") ObjectRepresentation.RIBBON else ObjectRepresentation.BALL_AND_STICK
                    val colorHex = if (o.isNull("colorHex")) null else o.optString("colorHex", null)
                    rebuilt.add(MolAppObject(name, type, o.optBoolean("isVisible", true), rep, colorHex))
                }
                objects.clear(); objects.addAll(rebuilt)
                body.optJSONObject("visibility")?.let { vis ->
                    featureVisibility.clear()
                    for (k in vis.keys()) featureVisibility[k] = vis.optBoolean(k)
                }
                return
            }
        }
        // Otherwise it is a command result: { id, command, success, error, label }.
        receiveResult(body)
    }

    private fun receiveResult(r: JSONObject) {
        val command = r.optString("command", null)
        val success = r.optBoolean("success", false)
        val label = if (r.isNull("label")) null else r.optString("label", null)
        if (!success) {
            if (status.endsWith("…") || status.startsWith("Loading")) status = "Ready for structure loading"
            error = if (r.isNull("error")) null else r.optString("error", null)
            return
        }
        error = null
        when (command) {
            "loadLocalStructure" -> status = "Loaded ${label ?: "Structure"}"
            "loadPdbId" -> status = "Loaded ${label ?: lastPdbName}"
            "setRepresentation" -> status = "$lastRepresentationTitle representation"
            "surfacePotential" -> status = "Electrostatic potential (screened Coulomb)"
            "startMorph" -> { isMorphing = true; status = "Morphing" }
            "stopMorph" -> { isMorphing = false; status = "Morph stopped" }
            "superpose" -> status = "Superposed visible structures"
            "secondaryStructure" -> status = "Secondary structure (helix/sheet/coil)"
            "resetAll" -> status = "Reset — everything cleared"
            "undo" -> status = "Undid last change"
            "redo" -> status = "Redid last change"
            "transientModesStopped" -> { measureKind = null; isMorphing = false }
        }
    }

    private fun addObject(obj: MolAppObject) {
        val idx = objects.indexOfFirst { it.name == obj.name }
        if (idx >= 0) objects[idx] = obj else objects.add(obj)
    }

    private fun updateObject(name: String, transform: (MolAppObject) -> MolAppObject) {
        val idx = objects.indexOfFirst { it.name == name }
        if (idx >= 0) objects[idx] = transform(objects[idx])
    }
}

private fun List<String>.toJsonArray() = org.json.JSONArray().also { for (s in this) it.put(s) }
