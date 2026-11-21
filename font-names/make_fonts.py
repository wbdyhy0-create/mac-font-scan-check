#!/usr/bin/env python3
"""Makes test fonts out of one free Hebrew font (Heebo, SIL Open Font License): the same letters in five weights, written to
files whose names and weight numbers are filled in the different ways font makers fill them in. A program that lists installed
fonts, and a web view that draws them, can then be checked against every way.

    python3 make_fonts.py <Heebo[wght].ttf> <folder for the fonts> <folder for the page's data>

Every family made here starts with "Probe". The letters of a weight are the same in every family, and each weight is as wide as no
other, so the width of a line of text tells which file drew it."""

import base64
import json
import os
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.qu2cuPen import Qu2CuPen
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

WEIGHTS = [(300, "Light"), (400, "Regular"), (500, "Medium"), (700, "Bold"), (900, "Black")]
WIN_EN = (3, 1, 0x409)
WIN_HE = (3, 1, 0x40D)
MAC_EN = (1, 0, 0)
UNI = (0, 3, 0)
SAMPLE = "אבגדהוזחטיכלמנסעפצקרשת"


def static_weights(source):
    """the five weights of the variable font, each as a font of its own"""
    made = {}
    for weight, _ in WEIGHTS:
        font = TTFont(source)
        font = instancer.instantiateVariableFont(font, {"wght": weight})
        for tag in ("STAT", "MVAR", "avar", "HVAR", "gvar", "fvar"):
            if tag in font:
                del font[tag]
        made[weight] = font
    return made


def to_cff(font, ps_name):
    """the same font with its outlines written the other way (the kind kept in .otf files)"""
    glyph_order = font.getGlyphOrder()
    glyph_set = font.getGlyphSet()
    char_strings = {}
    for name in glyph_order:
        pen = T2CharStringPen(font["hmtx"][name][0], glyph_set)
        glyph_set[name].draw(Qu2CuPen(pen, max_err=1.0, all_cubic=True))
        char_strings[name] = pen.getCharString()
    builder = FontBuilder(font["head"].unitsPerEm, isTTF=False)
    builder.setupGlyphOrder(glyph_order)
    builder.setupCharacterMap(font.getBestCmap())
    builder.setupCFF(ps_name, {"FullName": ps_name}, char_strings, {})
    builder.setupHorizontalMetrics({name: font["hmtx"][name] for name in glyph_order})
    builder.setupHorizontalHeader(ascent=font["hhea"].ascent, descent=font["hhea"].descent)
    builder.setupNameTable({})
    builder.setupOS2(sTypoAscender=font["OS/2"].sTypoAscender, sTypoDescender=font["OS/2"].sTypoDescender, usWinAscent=font["OS/2"].usWinAscent, usWinDescent=font["OS/2"].usWinDescent)
    builder.setupPost()
    # the rules of the letters (which follow which, how close) go along, so that a line is as wide as in the other kind
    for tag in ("GDEF", "GPOS", "GSUB"):
        if tag in font:
            builder.font[tag] = font[tag]
    return builder.font


def write(font, path, records, weight_number, bold_bit=False):
    """saves the font with these names (a list of (platform, name id, text)) and this weight number"""
    table = font["name"]
    table.names = []
    for platform, name_id, text in records:
        table.setName(text, name_id, *platform)
    font["OS/2"].usWeightClass = weight_number
    selection = font["OS/2"].fsSelection & ~0b1100001
    font["OS/2"].fsSelection = selection | (0b100000 if bold_bit else 0b1000000)
    font["head"].macStyle = 1 if bold_bit else 0
    font.save(path)


def names(platforms, family, sub, full, ps, typo_family=None, typo_sub=None):
    records = []
    for platform in platforms:
        records += [(platform, 1, family), (platform, 2, sub), (platform, 4, full), (platform, 6, ps)]
        if typo_family:
            records += [(platform, 16, typo_family), (platform, 17, typo_sub)]
    return records


def main():
    source, fonts_dir, data_dir = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(fonts_dir, exist_ok=True)
    os.makedirs(data_dir, exist_ok=True)
    weights = static_weights(source)
    both = [WIN_EN, MAC_EN]
    families = []

    def face(file_name, weight, records, number, bold_bit=False, cff=False):
        font = weights[weight]
        if cff:
            font = to_cff(font, file_name.rsplit(".", 1)[0])
        write(font, os.path.join(fonts_dir, file_name), records, number, bold_bit)

    def family(key, about, try_names, files):
        families.append({"key": key, "about": about, "tryNames": try_names, "files": files})

    # 1. every weight a family of its own in the old names, no joint family name
    made = []
    for weight, word in WEIGHTS:
        linked = word in ("Regular", "Bold")
        fam = "Probe Sep" if linked else f"Probe Sep {word}"
        sub = word if linked else "Regular"
        full = "Probe Sep" if word == "Regular" else f"Probe Sep {word}"
        face(f"ProbeSep-{word}.ttf", weight, names(both, fam, sub, full, f"ProbeSep-{word}"), weight, word == "Bold")
        made.append({"file": f"ProbeSep-{word}.ttf", "letters": weight})
    family("sep", "each weight a family of its own (old names only)", ["Probe Sep", "Probe Sep Light", "Probe Sep Medium", "Probe Sep Black", "ProbeSep-Light", "ProbeSep-Black"], made)

    # 2. the same, with the joint family name and the weight names beside the old ones
    def joint(prefix, label, ending, cff, number_of, words=None, ps_of=None):
        made = []
        for weight, word in WEIGHTS:
            shown = (words or {}).get(weight, word)
            if words is not None and weight not in words:
                continue
            linked = shown in ("Regular", "Bold")
            fam = label if linked else f"{label} {shown}"
            sub = shown if linked else "Regular"
            full = label if shown == "Regular" else f"{label} {shown}"
            ps = ps_of(shown) if ps_of else f"{prefix}-{shown}"
            file_name = f"{prefix}-{shown}.{ending}"
            face(file_name, weight, names(both, fam, sub, full, ps, label, shown), number_of(weight), number_of(weight) >= 700 and shown == "Bold", cff)
            made.append({"file": file_name, "letters": weight, "ps": ps, "word": shown})
        return made

    family("typo", "one family by the joint name, right weight numbers", ["Probe Typo", "Probe Typo Light", "Probe Typo Black", "ProbeTypo-Light", "ProbeTypo-Black"], joint("ProbeTypo", "Probe Typo", "ttf", False, lambda w: w))
    # 3. one family, every file writes the same weight number
    family("same", "one family, every file writes weight 400", ["Probe Same", "Probe Same Light", "Probe Same Black", "ProbeSame-Light", "ProbeSame-Black"], joint("ProbeSame", "Probe Same", "ttf", False, lambda w: 400))
    # 4. the same, and the weights are named by words a list of weight words may not have
    family("odd", "every file writes 400, weights named Hair / Book / Fat", ["Probe Odd", "Probe Odd Hair", "Probe Odd Fat", "ProbeOdd-Hair", "ProbeOdd-Fat"], joint("ProbeOdd", "Probe Odd", "ttf", False, lambda w: 400, {300: "Hair", 500: "Book", 900: "Fat"}))
    # 5. the same, and the short name of each file has no hyphen before the weight
    family("glued", "every file writes 400, short names with no hyphen", ["Probe Glued", "Probe Glued Light", "Probe Glued Black", "ProbeGluedLight", "ProbeGluedBlack"], joint("ProbeGlued", "Probe Glued", "ttf", False, lambda w: 400, {300: "Light", 400: "Regular", 900: "Black"}, lambda shown: "ProbeGlued" if shown == "Regular" else f"ProbeGlued{shown}"))
    # 6. some weights share a number: Medium written as 400, Black as 700
    family("mix", "Medium written as 400 and Black as 700", ["Probe Mix", "Probe Mix Medium", "Probe Mix Black"], joint("ProbeMix", "Probe Mix", "ttf", False, lambda w: {500: 400, 900: 700}.get(w, w)))
    # 7. the other kind of outlines, in .otf files
    family("cff", "one family by the joint name, .otf files", ["Probe Cff", "Probe Cff Light", "Probe Cff Black", "ProbeCff-Light"], joint("ProbeCff", "Probe Cff", "otf", True, lambda w: w))
    # 8. .otf files that all write the same weight number
    family("cffsame", ".otf files, every file writes weight 400", ["Probe CffSame", "Probe CffSame Light", "Probe CffSame Black"], joint("ProbeCffSame", "Probe CffSame", "otf", True, lambda w: 400))

    # 9. a regular and a bold told apart by the bold mark only (both write 400)
    face("ProbeLink-Regular.ttf", 400, names(both, "Probe Link", "Regular", "Probe Link", "ProbeLink-Regular"), 400)
    face("ProbeLink-Bold.ttf", 700, names(both, "Probe Link", "Bold", "Probe Link Bold", "ProbeLink-Bold"), 400, True)
    family("link", "regular and bold both write 400, the bold has the bold mark", ["Probe Link", "Probe Link Bold", "ProbeLink-Bold"], [{"file": "ProbeLink-Regular.ttf", "letters": 400}, {"file": "ProbeLink-Bold.ttf", "letters": 700}])

    # 10. Hebrew names
    def pair(prefix, records_of):
        face(f"{prefix}-Regular.ttf", 400, records_of("Regular", f"{prefix}-Regular"), 400)
        face(f"{prefix}-Bold.ttf", 700, records_of("Bold", f"{prefix}-Bold"), 700, True)
        return [{"file": f"{prefix}-Regular.ttf", "letters": 400}, {"file": f"{prefix}-Bold.ttf", "letters": 700}]

    heb_a = "בדיקה א"
    family("heb-a", "an English name and a Hebrew name, each marked with its language", ["Probe HebA", heb_a, "ProbeHebA-Regular"], pair("ProbeHebA", lambda sub, ps: names(both, "Probe HebA", sub, "Probe HebA" + ("" if sub == "Regular" else " Bold"), ps) + [(WIN_HE, 1, heb_a), (WIN_HE, 2, sub), (WIN_HE, 4, heb_a)]))
    heb_b = "בדיקה ב"
    family("heb-b", "only a Hebrew name, marked as Hebrew (the short name is in Latin letters)", [heb_b, "ProbeHebB-Regular", "ProbeHebB"], pair("ProbeHebB", lambda sub, ps: [(WIN_HE, 1, heb_b), (WIN_HE, 2, sub), (WIN_HE, 4, heb_b), (WIN_EN, 6, ps)]))
    heb_c = "בדיקה ג"
    family("heb-c", "a Hebrew name written where the English name goes", [heb_c, "ProbeHebC-Regular", "ProbeHebC"], pair("ProbeHebC", lambda sub, ps: [(WIN_EN, 1, heb_c), (WIN_EN, 2, sub), (WIN_EN, 4, heb_c), (WIN_EN, 6, ps)]))
    heb_d = "בדיקה ד"
    family("heb-d", "a Hebrew name that comes first in the file, an English name after it", ["Probe HebD", heb_d, "ProbeHebD-Regular"], pair("ProbeHebD", lambda sub, ps: [(UNI, 1, heb_d), (UNI, 2, sub), (WIN_EN, 1, "Probe HebD"), (WIN_EN, 2, sub), (WIN_EN, 4, "Probe HebD" + ("" if sub == "Regular" else " Bold")), (WIN_EN, 6, ps)]))

    # 11. the name written for the Mac is another name than the one written for Windows
    family("macwin", "one family name in the Mac names, another in the Windows names", ["Probe WinSide", "Probe MacSide", "ProbeMacWin-Regular"], pair("ProbeMacWin", lambda sub, ps: [(MAC_EN, 1, "Probe MacSide"), (MAC_EN, 2, sub), (MAC_EN, 4, "Probe MacSide" + ("" if sub == "Regular" else " Bold")), (MAC_EN, 6, ps), (WIN_EN, 1, "Probe WinSide"), (WIN_EN, 2, sub), (WIN_EN, 4, "Probe WinSide" + ("" if sub == "Regular" else " Bold")), (WIN_EN, 6, ps)]))
    # 12. the joint family name only in the Windows names; the Mac names have the old names alone
    made = []
    for weight, word in WEIGHTS:
        linked = word in ("Regular", "Bold")
        fam = "Probe Half" if linked else f"Probe Half {word}"
        sub = word if linked else "Regular"
        full = "Probe Half" if word == "Regular" else f"Probe Half {word}"
        records = names([MAC_EN], fam, sub, full, f"ProbeHalf-{word}") + names([WIN_EN], fam, sub, full, f"ProbeHalf-{word}", "Probe Half", word)
        face(f"ProbeHalf-{word}.ttf", weight, records, weight, word == "Bold")
        made.append({"file": f"ProbeHalf-{word}.ttf", "letters": weight})
    family("half", "the joint family name only in the Windows names", ["Probe Half", "Probe Half Light", "Probe Half Black"], made)
    # 13. no short (PostScript) name at all
    face("ProbeNoShort-Regular.ttf", 400, [(p, i, t) for p in both for i, t in ((1, "Probe NoShort"), (2, "Regular"), (4, "Probe NoShort"))], 400)
    family("noshort", "a file with no short (PostScript) name", ["Probe NoShort"], [{"file": "ProbeNoShort-Regular.ttf", "letters": 400}])

    # what the page needs: the five weights as files to compare with (and to load by hand), and the names to try
    def b64(path):
        with open(path, "rb") as handle:
            return base64.b64encode(handle.read()).decode("ascii")

    refs = {}
    for weight, word in WEIGHTS:
        refs[str(weight)] = {"ttf": b64(os.path.join(fonts_dir, f"ProbeTypo-{word}.ttf")), "otf": b64(os.path.join(fonts_dir, f"ProbeCff-{word}.otf"))}
    with open(os.path.join(data_dir, "probe-data.js"), "w", encoding="utf-8") as handle:
        handle.write("window.PROBE = " + json.dumps({"sample": SAMPLE, "refs": refs, "families": families}, ensure_ascii=False) + ";\n")

    print("files made:", len(os.listdir(fonts_dir)))
    for weight, _ in WEIGHTS:
        font = weights[weight]
        cmap = font.getBestCmap()
        print(f"  width of the sample in weight {weight}: {sum(font['hmtx'][cmap[ord(c)]][0] for c in SAMPLE)} units")


if __name__ == "__main__":
    main()
