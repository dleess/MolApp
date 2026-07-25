package com.donghan.molapp

import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Log
import android.webkit.ConsoleMessage
import android.webkit.WebChromeClient
import android.webkit.WebView
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView

// Structure / state files above this are rejected before reading, to avoid OOM on huge inputs.
private const val MAX_FILE_BYTES = 64L * 1024 * 1024

class MainActivity : ComponentActivity() {

    private val bridge = MolStarBridge()
    private lateinit var controller: ViewerController
    private lateinit var openDoc: ActivityResultLauncher<Array<String>>
    private lateinit var openStateDoc: ActivityResultLauncher<Array<String>>
    private lateinit var createDoc: ActivityResultLauncher<String>
    private var pendingSaveBytes: ByteArray? = null
    private var webView: WebView? = null
    // A SAF picker takes ~1s to appear, so an impatient second tap used to stack a second picker
    // activity on top of the first. One back press then only closed the top one and the screen
    // looked unchanged — it read as "the file window won't close". Cleared in onResume, which is
    // the one point we are guaranteed to pass through on the way back from any picker.
    private var pickerOpen = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        controller = ViewerController(bridge)

        openDoc = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            uri?.let { loadLocalStructure(it) }
        }
        openStateDoc = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            uri?.let { openState(it) }
        }
        // One CreateDocument launcher for every save/export; the pending bytes + suggested filename
        // extension (set right before launch) determine what gets written and how apps open it.
        createDoc = registerForActivityResult(ActivityResultContracts.CreateDocument("*/*")) { uri ->
            val bytes = pendingSaveBytes
            pendingSaveBytes = null
            if (uri != null && bytes != null) writeToUri(uri, bytes)
        }

        val wv = createWebView()
        webView = wv

        val fileActions = FileActions(
            onOpenStructure = { launchOnce(openDoc, arrayOf("*/*")) },
            onSaveState = { saveState() },
            onOpenState = { launchOnce(openStateDoc, arrayOf("*/*")) },
            onExport = { exportImage(it) },
            onPrint = { printDisplay() },
        )

        setContent {
            MaterialTheme(colorScheme = androidx.compose.material3.darkColorScheme()) {
                ViewerScreen(controller, wv, fileActions)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun createWebView(): WebView = WebView(this).apply {
        if (BuildConfig.DEBUG) WebView.setWebContentsDebuggingEnabled(true)
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.allowFileAccess = true
        settings.allowContentAccess = true
        settings.allowFileAccessFromFileURLs = true
        // Lets the file:// viewer fetch structures from RCSB (cross-origin) for PDB-id loads.
        settings.allowUniversalAccessFromFileURLs = true
        setBackgroundColor(0xFF0B0B0F.toInt())
        webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(m: ConsoleMessage): Boolean {
                Log.d("MolApp/JS", "${m.message()} @${m.sourceId()}:${m.lineNumber()}")
                return true
            }
        }
        addJavascriptInterface(bridge, "MolAppAndroid")
        bridge.attach(this)
        loadUrl("file:///android_asset/viewer.html")
    }

    /** Launches a SAF picker unless one is already up. Returns false only if the launch itself failed. */
    private fun <I> launchOnce(launcher: ActivityResultLauncher<I>, input: I): Boolean {
        if (pickerOpen) return true
        pickerOpen = true
        return runCatching { launcher.launch(input) }.isSuccess.also { if (!it) pickerOpen = false }
    }

    override fun onResume() {
        super.onResume()
        pickerOpen = false
    }

    private fun loadLocalStructure(uri: Uri) {
        try {
            val name = queryDisplayName(uri) ?: "structure"
            val format = when (name.substringAfterLast('.', "").lowercase()) {
                "pdb" -> "pdb"
                "cif", "mmcif" -> "mmcif"
                else -> { bridge.updateError("Unsupported structure file type: $name"); return }
            }
            // Guard on the provider-reported size BEFORE reading, so a huge file is rejected instead
            // of OOM-crashing the read itself.
            querySize(uri)?.let { if (it > MAX_FILE_BYTES) { bridge.updateError("Structure file is too large."); return } }
            val text = contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
            if (text == null) { bridge.updateError("Could not read $name."); return }
            bridge.clearError()
            bridge.updateStatus("Loading $name")
            bridge.loadLocalStructure(text, format, name)
        } catch (e: Exception) {
            bridge.updateError(e.message ?: "Could not open file.")
        }
    }

    // ---- File ▸ Save / Open State (.molapp) -----------------------------------------------------

    private fun saveState() {
        if (bridge.objects.isEmpty()) { bridge.updateError("Nothing to save yet."); return }
        bridge.clearError()
        bridge.updateStatus("Capturing state…")
        bridge.requestSerializedState { json ->
            if (json.isNullOrEmpty()) { bridge.updateError("Could not capture current state."); return@requestSerializedState }
            pendingSaveBytes = json.toByteArray(Charsets.UTF_8)
            bridge.updateStatus("Choose where to save…")
            if (!launchOnce(createDoc, "molecule.molapp")) bridge.updateError("Could not open the save dialog.")
        }
    }

    private fun openState(uri: Uri) {
        try {
            querySize(uri)?.let { if (it > MAX_FILE_BYTES) { bridge.updateError("State file is too large."); return } }
            val text = contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
            if (text.isNullOrEmpty()) { bridge.updateError("Could not read .molapp file."); return }
            bridge.clearError()
            bridge.updateStatus("Loading state…")
            bridge.loadState(text)
        } catch (e: Exception) {
            bridge.updateError(e.message ?: "Could not open state file.")
        }
    }

    // ---- File ▸ Export Display / Print ----------------------------------------------------------

    private fun exportImage(format: ExportFormat) {
        if (bridge.objects.isEmpty()) { bridge.updateError("Nothing to export yet."); return }
        bridge.clearError()
        bridge.updateStatus("Rendering ${format.title}…")
        bridge.requestImageDataUrl { dataUrl ->
            val bmp = dataUrl?.let(::bitmapFromDataUrl)
            if (bmp == null) { bridge.updateError("Could not capture the display."); return@requestImageDataUrl }
            val bytes = runCatching { encodeImage(bmp, format) }.getOrNull()
            if (bytes == null) { bridge.updateError("Could not encode ${format.title}."); return@requestImageDataUrl }
            pendingSaveBytes = bytes
            bridge.updateStatus("Choose where to save…")
            if (!launchOnce(createDoc, "molecule.${format.ext}")) bridge.updateError("Could not open the save dialog.")
        }
    }

    private fun printDisplay() {
        if (bridge.objects.isEmpty()) { bridge.updateError("Nothing to print yet."); return }
        bridge.clearError()
        bridge.updateStatus("Rendering for print…")
        bridge.requestImageDataUrl { dataUrl ->
            val bmp = dataUrl?.let(::bitmapFromDataUrl)
            if (bmp == null) { bridge.updateError("Could not capture the display."); return@requestImageDataUrl }
            runCatching { androidx.print.PrintHelper(this).apply { scaleMode = androidx.print.PrintHelper.SCALE_MODE_FIT }.printBitmap("MolApp", bmp) }
                .onFailure { bridge.updateError("Printing is unavailable on this device.") }
        }
    }

    private fun writeToUri(uri: Uri, bytes: ByteArray) {
        try {
            val stream = contentResolver.openOutputStream(uri)
            if (stream == null) { bridge.updateError("Could not write the file."); return }
            stream.use { it.write(bytes) }
            bridge.updateStatus("Saved")
        } catch (e: Exception) {
            bridge.updateError(e.message ?: "Could not write the file.")
        }
    }

    // Mol* hands back a `data:image/png;base64,...` URL; decode it, then re-wrap natively per format.
    private fun bitmapFromDataUrl(dataUrl: String): android.graphics.Bitmap? {
        val comma = dataUrl.indexOf(',')
        if (comma < 0) return null
        return runCatching {
            val bytes = android.util.Base64.decode(dataUrl.substring(comma + 1), android.util.Base64.DEFAULT)
            android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        }.getOrNull()
    }

    private fun encodeImage(bmp: android.graphics.Bitmap, format: ExportFormat): ByteArray = when (format) {
        ExportFormat.PNG -> java.io.ByteArrayOutputStream().also { bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
        ExportFormat.JPEG -> java.io.ByteArrayOutputStream().also { bmp.compress(android.graphics.Bitmap.CompressFormat.JPEG, 95, it) }.toByteArray()
        ExportFormat.GIF -> GifEncoder.encode(bmp)
        ExportFormat.SVG -> svgWrap(bmp)
        ExportFormat.PDF -> pdfFromBitmap(bmp)
    }

    // A WebGL viewport is raster, so wrap the PNG in an SVG <image> — opens anywhere an .svg is
    // expected. ponytail: known ceiling, raster inside vector (mirrors iOS svgData).
    private fun svgWrap(bmp: android.graphics.Bitmap): ByteArray {
        val png = java.io.ByteArrayOutputStream().also { bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
        val b64 = android.util.Base64.encodeToString(png, android.util.Base64.NO_WRAP)
        val svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" " +
            "width=\"${bmp.width}\" height=\"${bmp.height}\" viewBox=\"0 0 ${bmp.width} ${bmp.height}\">" +
            "<image width=\"${bmp.width}\" height=\"${bmp.height}\" xlink:href=\"data:image/png;base64,$b64\"/></svg>"
        return svg.toByteArray(Charsets.UTF_8)
    }

    private fun pdfFromBitmap(bmp: android.graphics.Bitmap): ByteArray {
        val doc = android.graphics.pdf.PdfDocument()
        val page = doc.startPage(android.graphics.pdf.PdfDocument.PageInfo.Builder(bmp.width, bmp.height, 1).create())
        page.canvas.drawBitmap(bmp, 0f, 0f, null)
        doc.finishPage(page)
        val out = java.io.ByteArrayOutputStream()
        doc.writeTo(out)
        doc.close()
        return out.toByteArray()
    }

    private fun queryDisplayName(uri: Uri): String? =
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }

    // Bytes reported by the provider, or null when unknown (some streamed providers omit SIZE).
    private fun querySize(uri: Uri): Long? =
        contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { c ->
            if (c.moveToFirst() && !c.isNull(0)) c.getLong(0) else null
        }

    override fun onDestroy() {
        webView?.destroy()
        webView = null
        super.onDestroy()
    }
}

// ---- Compose UI ---------------------------------------------------------------------------------

private val PanelBg = Color(0xFF111114).copy(alpha = 0.82f)
private val BarBg = Color.Black.copy(alpha = 0.68f)

// File-menu actions that need Activity-level plumbing (SAF pickers, print). Mirrors the iOS File menu.
class FileActions(
    val onOpenStructure: () -> Unit,
    val onSaveState: () -> Unit,
    val onOpenState: () -> Unit,
    val onExport: (ExportFormat) -> Unit,
    val onPrint: () -> Unit,
)

@Composable
private fun ViewerScreen(controller: ViewerController, webView: WebView, actions: FileActions) {
    val bridge = controller.bridge
    Box(Modifier.fillMaxSize().background(Color(0xFF0B0B0F))) {
        AndroidView(factory = { webView }, modifier = Modifier.fillMaxSize())

        Column(Modifier.fillMaxSize().systemBarsPadding()) {
            MenuBar(controller, bridge, actions)
            InfoCard(controller, bridge, actions.onOpenStructure)
            Spacer(Modifier.weight(1f))
            bridge.measureKind?.let {
                Text(
                    "${it.title} mode — tap ${it.atomCount} atoms",
                    color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.align(Alignment.CenterHorizontally)
                        .background(Color(0xFF1D6FE0), RoundedCornerShape(20.dp))
                        .padding(horizontal = 12.dp, vertical = 6.dp)
                )
            }
            ObjectsPanel(bridge)
            CommandBar(controller)
        }
    }
}

@Composable
private fun MenuBar(controller: ViewerController, bridge: MolStarBridge, actions: FileActions) {
    val hasStructures = bridge.visibleStructureNames.isNotEmpty()
    val hasObjects = bridge.objects.isNotEmpty()
    Row(
        Modifier.fillMaxWidth().background(BarBg)
            .horizontalScroll(rememberScrollState()).padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TopMenu("File") { dismiss ->
            DropdownMenuItem(text = { Text("Open Structure") }, onClick = { dismiss(); actions.onOpenStructure() })
            DropdownMenuItem(text = { Text("Load PDB ID") }, enabled = controller.pdbText.isNotBlank(),
                onClick = { dismiss(); controller.loadPdb() })
            HorizontalDivider(color = Color.White.copy(alpha = 0.12f))
            DropdownMenuItem(text = { Text("Save State (.molapp)") }, enabled = hasObjects,
                onClick = { dismiss(); actions.onSaveState() })
            DropdownMenuItem(text = { Text("Open State (.molapp)") }, onClick = { dismiss(); actions.onOpenState() })
            HorizontalDivider(color = Color.White.copy(alpha = 0.12f))
            SectionLabel("Export Display")
            for (format in ExportFormat.entries) {
                DropdownMenuItem(text = { Text(format.title) }, enabled = hasObjects,
                    onClick = { dismiss(); actions.onExport(format) })
            }
            DropdownMenuItem(text = { Text("Print") }, enabled = hasObjects,
                onClick = { dismiss(); actions.onPrint() })
            HorizontalDivider(color = Color.White.copy(alpha = 0.12f))
            DropdownMenuItem(text = { Text("Reset All") }, onClick = {
                dismiss(); bridge.clearError(); bridge.resetAll(); bridge.updateStatus("Resetting…")
            })
        }
        TopMenu("Edit") { dismiss ->
            DropdownMenuItem(text = { Text("Undo") }, onClick = { dismiss(); bridge.clearError(); bridge.undo() })
            DropdownMenuItem(text = { Text("Redo") }, onClick = { dismiss(); bridge.clearError(); bridge.redo() })
            DropdownMenuItem(text = { Text("Clear Selection") }, onClick = { dismiss(); bridge.clearError(); bridge.clearSelection() })
        }
        TopMenu("Display") { dismiss ->
            SectionLabel("Representation")
            for (rep in MoleculeRepresentation.entries) {
                DropdownMenuItem(text = { Text(rep.title) }, enabled = hasStructures,
                    onClick = { dismiss(); controller.setRepresentation(rep) })
            }
            SectionLabel("Visibility")
            for (feature in MoleculeVisibilityFeature.entries) {
                val visible = bridge.featureVisibility[feature.raw] ?: true
                DropdownMenuItem(text = { Text("${if (visible) "Hide" else "Show"} ${feature.title}") },
                    onClick = { dismiss(); controller.toggleVisibility(feature) })
            }
            SectionLabel("Background")
            for (preset in backgroundPresets) {
                DropdownMenuItem(text = { Text(preset.title) }, onClick = {
                    dismiss(); bridge.clearError(); bridge.setBackgroundColor(preset.hex)
                    bridge.updateStatus("Background: ${preset.title}")
                })
            }
        }
        TopMenu("Calculation") { dismiss ->
            DropdownMenuItem(text = { Text("Surface Potential") }, enabled = hasStructures,
                onClick = { dismiss(); controller.surfacePotential() })
            DropdownMenuItem(text = { Text("Secondary Structure") }, enabled = hasStructures,
                onClick = { dismiss(); controller.secondaryStructure() })
            DropdownMenuItem(text = { Text("Superpose Visible") }, enabled = bridge.visibleStructureNames.size >= 2,
                onClick = { dismiss(); controller.superpose() })
            DropdownMenuItem(text = { Text(if (bridge.isMorphing) "Stop Morph" else "Start Morph") },
                enabled = bridge.isMorphing || hasStructures,
                onClick = { dismiss(); controller.morphToggle() })
        }
        TopMenu("Measure") { dismiss ->
            for (kind in MeasureKind.entries) {
                val active = bridge.measureKind == kind
                DropdownMenuItem(text = { Text("${kind.title} Mode${if (active) " ✓" else ""}") },
                    onClick = { dismiss(); controller.toggleMeasure(kind) })
            }
            DropdownMenuItem(text = { Text("Clear Measurements") }, onClick = { dismiss(); controller.clearMeasurements() })
        }
        TopMenu("Help") { dismiss ->
            DropdownMenuItem(text = { Text("Quick Help") },
                onClick = { dismiss(); bridge.updateStatus("Load a PDB ID or open a file · set the viewport background via Display ▸ Background") })
        }
    }
}

@Composable
private fun TopMenu(label: String, content: @Composable (dismiss: () -> Unit) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        Text(label, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 16.sp,
            modifier = Modifier.clickable { expanded = true }.padding(horizontal = 8.dp, vertical = 6.dp))
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            content { expanded = false }
        }
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(text, color = Color.Gray, fontSize = 11.sp, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
}

@Composable
private fun InfoCard(controller: ViewerController, bridge: MolStarBridge, onOpenStructure: () -> Unit) {
    Column(
        Modifier.padding(12.dp).background(PanelBg, RoundedCornerShape(8.dp)).padding(14.dp).widthIn(max = 320.dp)
    ) {
        Text("Molecule Viewer", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
        Text(bridge.status, color = Color.White.copy(alpha = 0.75f), fontSize = 14.sp,
            modifier = Modifier.padding(top = 2.dp))
        Text("Open Structure", color = Color.White, fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(top = 8.dp)
                .background(Color(0xFF1D6FE0), RoundedCornerShape(20.dp))
                .clickable { onOpenStructure() }.padding(horizontal = 16.dp, vertical = 8.dp))
        Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            TextField(
                value = controller.pdbText,
                onValueChange = { controller.pdbText = it.uppercase() },
                placeholder = { Text("PDB ID") },
                singleLine = true,
                modifier = Modifier.width(120.dp),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
                keyboardActions = KeyboardActions(onGo = { controller.loadPdb() }),
                colors = TextFieldDefaults.colors(),
            )
            Spacer(Modifier.width(8.dp))
            val enabled = controller.pdbText.isNotBlank()
            Text("Load PDB", color = if (enabled) Color.White else Color.White.copy(alpha = 0.3f),
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.background(Color.White.copy(alpha = 0.12f), RoundedCornerShape(8.dp))
                    .clickable(enabled = enabled) { controller.loadPdb() }
                    .padding(horizontal = 14.dp, vertical = 10.dp))
        }
        bridge.error?.let {
            Text(it, color = Color(0xFFFF6B6B), fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp))
        }
    }
}

@Composable
private fun ObjectsPanel(bridge: MolStarBridge) {
    var expanded by remember { mutableStateOf(true) }
    Column(
        Modifier.padding(start = 12.dp, end = 12.dp, bottom = 8.dp)
            .background(PanelBg, RoundedCornerShape(8.dp)).padding(10.dp).widthIn(max = 260.dp)
    ) {
        Row(Modifier.fillMaxWidth().clickable { expanded = !expanded }, verticalAlignment = Alignment.CenterVertically) {
            Text("Objects", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            Text(if (expanded) "▲" else "▼", color = Color.White, fontSize = 11.sp)
        }
        if (expanded) {
            if (bridge.objects.isEmpty()) {
                Text("No objects", color = Color.White.copy(alpha = 0.45f), fontSize = 12.sp,
                    modifier = Modifier.padding(top = 4.dp))
            } else {
                for (obj in bridge.objects) ObjectRow(bridge, obj)
            }
        }
    }
}

@Composable
private fun ObjectRow(bridge: MolStarBridge, obj: MolAppObject) {
    var showColorPicker by remember { mutableStateOf(false) }
    Column(Modifier.padding(top = 6.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(if (obj.isVisible) "◉" else "○", color = if (obj.isVisible) Color.White else Color.White.copy(alpha = 0.35f),
                modifier = Modifier.clickable { bridge.setObjectVisibility(obj.name, !obj.isVisible) }.padding(end = 6.dp))
            Column(Modifier.weight(1f)) {
                Text(obj.name, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Medium,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(obj.type, color = Color.White.copy(alpha = 0.45f), fontSize = 11.sp)
            }
            // Per-object color: swatch shows the current color; tap opens the Okabe-Ito picker (mirrors iOS).
            Box {
                Box(
                    Modifier.size(16.dp)
                        .background(obj.colorHex?.let(::colorFromHex) ?: Color.White.copy(alpha = 0.3f), CircleShape)
                        .border(0.5.dp, Color.White.copy(alpha = 0.3f), CircleShape)
                        .clickable { showColorPicker = true }
                )
                ColorPickerMenu(expanded = showColorPicker, onDismiss = { showColorPicker = false }) { hex ->
                    bridge.setObjectColor(obj.name, hex)
                    showColorPicker = false
                }
            }
        }
        Row(Modifier.padding(top = 2.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            for (rep in ObjectRepresentation.entries) {
                val active = obj.representation == rep
                Text(rep.shortTitle, fontSize = 10.sp, color = if (active) Color.White else Color.White.copy(alpha = 0.6f),
                    modifier = Modifier.background(
                        if (active) Color.White.copy(alpha = 0.25f) else Color.Transparent, RoundedCornerShape(3.dp)
                    ).clickable { bridge.setObjectRepresentation(obj.name, rep) }.padding(horizontal = 5.dp, vertical = 3.dp))
            }
        }
    }
}

// Okabe-Ito swatch picker, mirroring iOS's colorPickerPopover: "Default" clears the override (null hex),
// the rest map to the shared namedColors palette. Laid out 5 per row to match the iOS grid.
private val colorPickerKeys = listOf(
    "default", "red", "green", "blue", "yellow", "white", "cyan", "magenta", "orange",
)

@Composable
private fun ColorPickerMenu(expanded: Boolean, onDismiss: () -> Unit, onPick: (String?) -> Unit) {
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss, modifier = Modifier.background(Color(0xFF15151A))) {
        Text("Color", color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp))
        Column(Modifier.padding(horizontal = 10.dp, vertical = 4.dp)) {
            for (rowKeys in colorPickerKeys.chunked(5)) {
                Row(Modifier.padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (key in rowKeys) {
                        val hex = if (key == "default") null else colorNameToHex(key)
                        Box(
                            Modifier.size(26.dp)
                                .background(hex?.let(::colorFromHex) ?: Color.White.copy(alpha = 0.35f), CircleShape)
                                .border(0.5.dp, Color.White.copy(alpha = 0.35f), CircleShape)
                                .clickable { onPick(hex) }
                        )
                    }
                }
            }
        }
    }
}

/** Parse "#RRGGBB" to a Compose Color; falls back to a faint neutral for malformed values (JS-sourced). */
private fun colorFromHex(hex: String): Color =
    runCatching { Color(android.graphics.Color.parseColor(hex)) }.getOrDefault(Color.White.copy(alpha = 0.3f))

@Composable
private fun CommandBar(controller: ViewerController) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp)
            .background(Color.Black.copy(alpha = 0.75f), RoundedCornerShape(10.dp))
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TextField(
            value = controller.commandText,
            onValueChange = { controller.commandText = it },
            placeholder = { Text("Enter command (e.g. load 1crn, repr surface)...") },
            singleLine = true,
            modifier = Modifier.weight(1f).height(56.dp),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(onSend = { controller.executeCommand() }),
            colors = TextFieldDefaults.colors(),
        )
        Text("▶", color = if (controller.commandText.isNotBlank()) Color(0xFF3B82F6) else Color.White.copy(alpha = 0.3f),
            fontSize = 20.sp, modifier = Modifier.clickable { controller.executeCommand() }.padding(10.dp))
    }
}
