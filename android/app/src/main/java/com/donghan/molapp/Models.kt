package com.donghan.molapp

import org.json.JSONArray
import org.json.JSONObject

/** Structure-wide representation presets (Display menu). Mirrors iOS MoleculeRepresentation. */
enum class MoleculeRepresentation(val raw: String, val title: String) {
    RIBBON("ribbon", "Ribbon"),
    SURFACE("surface", "Surface"),
    STICK("stick", "Stick");

    companion object {
        fun fromRaw(raw: String) = entries.firstOrNull { it.raw == raw }
    }
}

/** Feature-visibility toggles (Display > Visibility). Mirrors iOS MoleculeVisibilityFeature. */
enum class MoleculeVisibilityFeature(val raw: String, val title: String) {
    PROTEIN("protein", "Protein"),
    WATER("water", "Water"),
    LIGAND("ligand", "Ligand");

    companion object {
        fun fromRaw(raw: String) = entries.firstOrNull { it.raw == raw }
    }
}

/** Per-object representations (Objects panel + `repr` command). Mirrors iOS ObjectRepresentation. */
enum class ObjectRepresentation(val raw: String, val title: String, val shortTitle: String) {
    RIBBON("ribbon", "Ribbon", "Rib"),
    SURFACE("surface", "Surface", "Sur"),
    STICK("stick", "Stick", "Stk"),
    BALL_AND_STICK("ballAndStick", "Ball+Stick", "B+S"),
    SPHERE("sphere", "Sphere", "Sph");

    companion object {
        fun fromRaw(raw: String) = entries.firstOrNull { it.raw.equals(raw, ignoreCase = true) }
    }
}

enum class MeasureKind(val raw: String, val title: String, val atomCount: Int) {
    DISTANCE("distance", "Distance", 2),
    ANGLE("angle", "Angle", 3),
    DIHEDRAL("dihedral", "Dihedral", 4);
}

data class MolAppObject(
    val name: String,
    val type: String,           // "structure" | "selection"
    val isVisible: Boolean = true,
    val representation: ObjectRepresentation = ObjectRepresentation.RIBBON,
    val colorHex: String? = null,
)

object PdbIdentifier {
    private val regex = Regex("^[A-Z0-9]{4}$")

    /** @throws IllegalArgumentException if not a 4-char PDB id. */
    fun normalized(raw: String): String {
        val id = raw.trim().uppercase()
        if (!regex.matches(id)) throw IllegalArgumentException("Enter a 4-character PDB ID.")
        return id
    }

    fun displayName(raw: String): String =
        runCatching { normalized(raw) }.getOrDefault(raw.trim().uppercase())
}

// Okabe-Ito colorblind-safe palette, matching the iOS command/color-picker names.
val namedColors: Map<String, String> = mapOf(
    "red" to "#D55E00", "green" to "#009E73", "blue" to "#0072B2",
    "yellow" to "#F0E442", "white" to "#FFFFFF", "cyan" to "#56B4E9",
    "magenta" to "#CC79A7", "orange" to "#E69F00",
)

fun colorNameToHex(name: String): String {
    if (name.startsWith("#")) return name
    return namedColors[name] ?: "#FFFFFF"
}

// Viewport background presets (dark → light), shared by the Display ▸ Background menu and the
// `background` command. Matches the iOS BackgroundPreset list.
data class BackgroundPreset(val title: String, val hex: String)

val backgroundPresets: List<BackgroundPreset> = listOf(
    BackgroundPreset("Dark", "#0B0F14"),
    BackgroundPreset("Black", "#000000"),
    BackgroundPreset("Gray", "#4D4D4D"),
    BackgroundPreset("Light", "#D9D9D9"),
    BackgroundPreset("White", "#FFFFFF"),
)

/** Selection AST node. Serializes to the same JSON shape the viewer's queryFromAST consumes. */
data class SelAst(
    val kind: String,
    val value: String? = null,
    val left: SelAst? = null,
    val right: SelAst? = null,
    val operand: SelAst? = null,
) {
    fun toJson(): JSONObject {
        val o = JSONObject()
        o.put("kind", kind)
        value?.let { o.put("value", it) }
        left?.let { o.put("left", JSONArray().put(it.toJson())) }
        right?.let { o.put("right", JSONArray().put(it.toJson())) }
        operand?.let { o.put("operand", JSONArray().put(it.toJson())) }
        return o
    }
}
