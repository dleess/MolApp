package com.donghan.molapp

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * UI-facing controller mirroring the iOS MoleculeViewerView action methods: holds the PDB-id and
 * command-bar text, and routes menu actions + the command parser to the bridge. Menus and the
 * command bar share these methods so both behave identically (as on iOS).
 */
class ViewerController(val bridge: MolStarBridge) {
    var pdbText by mutableStateOf("")
    var commandText by mutableStateOf("")

    private val visibleStructureNames: List<String> get() = bridge.visibleStructureNames

    fun loadPdb() {
        try {
            val pdbId = PdbIdentifier.normalized(pdbText)
            pdbText = pdbId
            bridge.updateStatus("Loading $pdbId")
            bridge.clearError()
            bridge.loadPdbId(pdbId)
        } catch (e: IllegalArgumentException) {
            bridge.updateError(e.message)
        }
    }

    fun setRepresentation(representation: MoleculeRepresentation) {
        bridge.clearError()
        bridge.setRepresentation(representation, visibleStructureNames)
    }

    fun toggleVisibility(feature: MoleculeVisibilityFeature) {
        val isVisible = !(bridge.featureVisibility[feature.raw] ?: true)
        bridge.featureVisibility[feature.raw] = isVisible
        bridge.clearError()
        bridge.updateStatus("${feature.title} ${if (isVisible) "shown" else "hidden"}")
        bridge.toggleVisibility(feature.raw, isVisible)
    }

    fun toggleMeasure(kind: MeasureKind) {
        bridge.clearError()
        if (bridge.measureKind == kind) {
            bridge.setMeasureMode(false, null)
            bridge.updateStatus("Measure mode off")
        } else {
            bridge.setMeasureMode(true, kind.raw)
            bridge.updateStatus("${kind.title}: tap ${kind.atomCount} atoms")
        }
    }

    fun surfacePotential() {
        bridge.clearError()
        bridge.updateStatus("Computing surface potential…")
        bridge.drawSurfacePotential(visibleStructureNames)
    }

    fun secondaryStructure() {
        bridge.clearError()
        bridge.updateStatus("Assigning secondary structure…")
        bridge.computeSecondaryStructure(visibleStructureNames)
    }

    fun superpose() {
        bridge.clearError()
        if (visibleStructureNames.size < 2) {
            bridge.updateError("Show at least two structures to superpose.")
            return
        }
        bridge.updateStatus("Superposing structures…")
        bridge.superpose(visibleStructureNames)
    }

    fun morphToggle() {
        bridge.clearError()
        if (bridge.isMorphing) {
            bridge.stopMorph()
        } else {
            bridge.updateStatus("Morphing trajectory…")
            bridge.startMorph(loop = false, targets = visibleStructureNames)
        }
    }

    fun clearMeasurements() {
        bridge.clearError()
        bridge.clearMeasurements()
        bridge.updateStatus("Measurements cleared")
    }

    /** Direct port of iOS executeCommand. */
    fun executeCommand() {
        val input = commandText.trim()
        if (input.isEmpty()) return
        commandText = ""
        bridge.clearError()

        val components = input.lowercase().split(Regex("\\s+")).filter { it.isNotEmpty() }
        // Keep original-case tokens for name arguments (PDB ids / file labels are case-sensitive).
        val rawComponents = input.split(Regex("\\s+")).filter { it.isNotEmpty() }
        val command = components.firstOrNull() ?: return

        when (command) {
            "load" -> if (components.size >= 2) {
                pdbText = components[1].uppercase(); loadPdb()
            } else bridge.updateError("Usage: load [PDB_ID]")

            "repr" -> when {
                components.size >= 3 -> {
                    val reprStr = components[1]
                    val objName = rawComponents.drop(2).joinToString(" ")
                    val repr = ObjectRepresentation.fromRaw(reprStr)
                    if (repr != null) bridge.setObjectRepresentation(objName, repr)
                    else bridge.updateError("Invalid representation. Use: ${ObjectRepresentation.entries.joinToString(", ") { it.raw }}")
                }
                components.size >= 2 -> {
                    val repr = MoleculeRepresentation.fromRaw(components[1])
                    if (repr != null) setRepresentation(repr)
                    else bridge.updateError("Invalid representation. Use: ${MoleculeRepresentation.entries.joinToString(", ") { it.raw }}")
                }
                else -> bridge.updateError("Usage: repr [ribbon|surface|stick|ballAndStick|sphere] [name?]")
            }

            "show", "hide" -> if (components.size >= 2) {
                val arg = components[1]
                val isVisible = command == "show"
                val feature = MoleculeVisibilityFeature.fromRaw(arg)
                if (feature != null) {
                    if ((bridge.featureVisibility[feature.raw] ?: true) != isVisible) toggleVisibility(feature)
                } else {
                    bridge.setObjectVisibility(rawComponents.drop(1).joinToString(" "), isVisible)
                }
            } else bridge.updateError("Usage: $command [water|ligand|objectname]")

            "select" -> {
                val afterSelect = input.drop(6).trim()
                if (afterSelect.isEmpty()) {
                    bridge.updateError("Usage: select [name] [expression] (e.g. select sele chain A & resn ala)")
                } else {
                    val (name, expression) = SelectionExpressionParser.extractName(afterSelect)
                    try {
                        val ast = SelectionExpressionParser(expression).parse()
                        bridge.setSelection("expression", "$name: $expression", ast)
                    } catch (e: SelectionExpressionParser.ParseException) {
                        bridge.updateError(e.message)
                    }
                }
            }

            "color" -> if (components.size >= 3) {
                val colorArg = components[1]
                val objName = rawComponents.drop(2).joinToString(" ")
                val colorHex = if (colorArg == "default") null else colorNameToHex(colorArg)
                bridge.setObjectColor(objName, colorHex)
            } else bridge.updateError("Usage: color [red|green|blue|yellow|white|cyan|magenta|orange|#RRGGBB|default] [name]")

            "clear" -> bridge.clearSelection()
            "focus" -> bridge.focusSelection()
            "surfpot", "potential" -> surfacePotential()
            "ss", "dssp", "secstr" -> secondaryStructure()
            "super", "superpose", "align" -> superpose()

            "morph" -> {
                val arg = if (components.size >= 2) components[1] else "start"
                if (arg == "stop") bridge.stopMorph()
                else {
                    val loop = components.contains("loop")
                    bridge.updateStatus("Morphing trajectory…")
                    bridge.startMorph(loop, visibleStructureNames)
                }
            }

            "measure", "dist" -> {
                val arg = if (components.size >= 2) components[1] else "distance"
                when (arg) {
                    "clear" -> clearMeasurements()
                    "off" -> bridge.measureKind?.let { toggleMeasure(it) }
                    "angle" -> if (bridge.measureKind != MeasureKind.ANGLE) toggleMeasure(MeasureKind.ANGLE)
                    "dihedral", "torsion" -> if (bridge.measureKind != MeasureKind.DIHEDRAL) toggleMeasure(MeasureKind.DIHEDRAL)
                    else -> if (bridge.measureKind != MeasureKind.DISTANCE) toggleMeasure(MeasureKind.DISTANCE)
                }
            }

            else -> bridge.updateError("Unknown command: $command")
        }
    }
}
