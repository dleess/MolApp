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
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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

class MainActivity : ComponentActivity() {

    private val bridge = MolStarBridge()
    private lateinit var controller: ViewerController
    private lateinit var openDoc: ActivityResultLauncher<Array<String>>
    private var webView: WebView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        controller = ViewerController(bridge)

        openDoc = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            uri?.let { loadLocalStructure(it) }
        }

        val wv = createWebView()
        webView = wv

        setContent {
            MaterialTheme(colorScheme = androidx.compose.material3.darkColorScheme()) {
                ViewerScreen(controller, wv, onOpenStructure = { openDoc.launch(arrayOf("*/*")) })
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun createWebView(): WebView = WebView(this).apply {
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

    private fun loadLocalStructure(uri: Uri) {
        try {
            val name = queryDisplayName(uri) ?: "structure"
            val format = when (name.substringAfterLast('.', "").lowercase()) {
                "pdb" -> "pdb"
                "cif", "mmcif" -> "mmcif"
                else -> { bridge.updateError("Unsupported structure file type: $name"); return }
            }
            val text = contentResolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
            if (text == null) { bridge.updateError("Could not read $name."); return }
            if (text.toByteArray().size > 64 * 1024 * 1024) { bridge.updateError("Structure file is too large."); return }
            bridge.clearError()
            bridge.updateStatus("Loading $name")
            bridge.loadLocalStructure(text, format, name)
        } catch (e: Exception) {
            bridge.updateError(e.message ?: "Could not open file.")
        }
    }

    private fun queryDisplayName(uri: Uri): String? =
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
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

@Composable
private fun ViewerScreen(controller: ViewerController, webView: WebView, onOpenStructure: () -> Unit) {
    val bridge = controller.bridge
    Box(Modifier.fillMaxSize().background(Color(0xFF0B0B0F))) {
        AndroidView(factory = { webView }, modifier = Modifier.fillMaxSize())

        Column(Modifier.fillMaxSize().systemBarsPadding()) {
            MenuBar(controller, bridge, onOpenStructure)
            InfoCard(controller, bridge, onOpenStructure)
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
private fun MenuBar(controller: ViewerController, bridge: MolStarBridge, onOpenStructure: () -> Unit) {
    val hasStructures = bridge.visibleStructureNames.isNotEmpty()
    Row(
        Modifier.fillMaxWidth().background(BarBg)
            .horizontalScroll(rememberScrollState()).padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TopMenu("File") { dismiss ->
            DropdownMenuItem(text = { Text("Open Structure") }, onClick = { dismiss(); onOpenStructure() })
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
                onClick = { dismiss(); bridge.updateStatus("Open a PDB/mmCIF file or enter a PDB ID") })
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
    Column(Modifier.padding(top = 6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(if (obj.isVisible) "◉" else "○", color = if (obj.isVisible) Color.White else Color.White.copy(alpha = 0.35f),
                modifier = Modifier.clickable { bridge.setObjectVisibility(obj.name, !obj.isVisible) }.padding(end = 6.dp))
            Column {
                Text(obj.name, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Medium,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(obj.type, color = Color.White.copy(alpha = 0.45f), fontSize = 11.sp)
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
        // ponytail: per-object color set via the `color <name> <object>` command; no swatch row in the
        // panel yet. Add a color picker here if touch color-setting is requested.
    }
}

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
