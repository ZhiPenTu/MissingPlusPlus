#!/usr/bin/env python3
"""Wire the asset catalog and mood menu bar icons into
MissingPlusPlus.xcodeproj/project.pbxproj.

Existing IDs already in use (we picked non-conflicting ones):
  A0000001 = Assets.xcassets in Resources
  A0000002 = MenuBarIcon.png in Resources
  A0000010..A0000014  : 5 mood menu bar PNGs
  A0000020..A0000024  : 5 mood alt .icns
  B0000001 = product, B0000002 = Info.plist, B0000003 = entitlements
  B0000004 = Assets.xcassets (file ref)
  B0000005 = MenuBarIcon.png
  B0000010..B0000014  : 5 mood menu bar PNGs
  B0000020..B0000024  : 5 mood alt .icns
  D0000007 = Resources group
  D0000010 = Assets.xcassets sub-group
  A1000001..A1000009 = Swift sources
  B1000001..B1000009 = Swift file refs

Idempotency: each insertion is guarded by a sentinel check that looks for
the FULL line (with the `= {isa = ...` part) so re-runs won't add duplicates
just because an ID is mentioned elsewhere (e.g. in a build file).

Use `--force` to ignore the idempotency check and re-insert everything.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

PBXPROJ = Path("/Users/tuzhipeng/missing++/MissingPlusPlus.xcodeproj/project.pbxproj")
BACKUP = PBXPROJ.with_suffix(".pbxproj.bak")

BUILD_XCASSETS    = "A0000001000000000000A001"
BUILD_MENU_DEFAULT= "A0000002000000000000A001"
REF_XCASSETS      = "B0000004000000000000A001"
REF_MENU_DEFAULT  = "B0000005000000000000A001"
GROUP_XCASSETS    = "D000001000000000000A001"

MOOD_BUILDS = {
    "happy":     "A000001000000000000A001",
    "joyful":    "A000001100000000000A001",
    "delighted": "A000001200000000000A001",
    "sad":       "A000001300000000000A001",
    "longing":   "A000001400000000000A001",
}
MOOD_REFS = {
    "happy":     "B000001000000000000A001",
    "joyful":    "B000001100000000000A001",
    "delighted": "B000001200000000000A001",
    "sad":       "B000001300000000000A001",
    "longing":   "B000001400000000000A001",
}

ALT_BUILDS = {
    "happy":     "A000002000000000000A001",
    "joyful":    "A000002100000000000A001",
    "delighted": "A000002200000000000A001",
    "sad":       "A000002300000000000A001",
    "longing":   "A000002400000000000A001",
}
ALT_REFS = {
    "happy":     "B000002000000000000A001",
    "joyful":    "B000002100000000000A001",
    "delighted": "B000002200000000000A001",
    "sad":       "B000002300000000000A001",
    "longing":   "B000002400000000000A001",
}


def patch(text: str, force: bool = False) -> str:
    # 1. PBXBuildFile for Assets.xcassets (replaces the original AppIcon.icns slot).
    if force or f"{BUILD_XCASSETS} /* Assets.xcassets in Resources */" not in text:
        text = re.sub(
            r"A0000001000000000000A001 /\* AppIcon\.icns in Resources \*/ = \{isa = PBXBuildFile; fileRef = B0000004000000000000A001 /\* AppIcon\.icns \*/; \};",
            f"{BUILD_XCASSETS} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {REF_XCASSETS} /* Assets.xcassets */; }};",
            text,
        )

    # 2. PBXFileReference for Assets.xcassets.
    if force or "lastKnownFileType = folder.assetcatalog" not in text:
        text = re.sub(
            r"B0000004000000000000A001 /\* AppIcon\.icns \*/ = \{isa = PBXFileReference; lastKnownFileType = image\.icns; path = AppIcon\.icns; sourceTree = \"<group>\"; \};",
            f"{REF_XCASSETS} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; }};",
            text,
        )

    # 3. PBXBuildFile for the 5 mood menu bar PNGs.
    for mood, build_id in MOOD_BUILDS.items():
        ref_id = MOOD_REFS[mood]
        sentinel = f"{build_id} /* MenuBarIcon-{mood}.png in Resources */ = {{isa = PBXBuildFile"
        if not force and sentinel in text:
            continue
        line = (
            f"		{build_id} /* MenuBarIcon-{mood}.png in Resources */ = "
            f"{{isa = PBXBuildFile; fileRef = {ref_id} /* MenuBarIcon-{mood}.png */; }};\n"
        )
        text = text.replace("/* End PBXBuildFile section */",
                            line + "/* End PBXBuildFile section */")

    # 4. PBXFileReference for the 5 mood menu bar PNGs.
    for mood, ref_id in MOOD_REFS.items():
        sentinel = f"{ref_id} /* MenuBarIcon-{mood}.png */ = {{isa = PBXFileReference"
        if not force and sentinel in text:
            continue
        line = (
            f"		{ref_id} /* MenuBarIcon-{mood}.png */ = "
            f"{{isa = PBXFileReference; lastKnownFileType = image.png; path = MenuBarIcon-{mood}.png; sourceTree = \"<group>\"; }};\n"
        )
        text = text.replace("/* End PBXFileReference section */",
                            line + "/* End PBXFileReference section */")

    # 5. PBXBuildFile for the 5 alt .icns.
    for mood, build_id in ALT_BUILDS.items():
        ref_id = ALT_REFS[mood]
        sentinel = f"{build_id} /* AppIcon-{mood}.icns in Resources */ = {{isa = PBXBuildFile"
        if not force and sentinel in text:
            continue
        line = (
            f"		{build_id} /* AppIcon-{mood}.icns in Resources */ = "
            f"{{isa = PBXBuildFile; fileRef = {ref_id} /* AppIcon-{mood}.icns */; }};\n"
        )
        text = text.replace("/* End PBXBuildFile section */",
                            line + "/* End PBXBuildFile section */")

    # 6. PBXFileReference for the 5 alt .icns.
    for mood, ref_id in ALT_REFS.items():
        sentinel = f"{ref_id} /* AppIcon-{mood}.icns */ = {{isa = PBXFileReference"
        if not force and sentinel in text:
            continue
        line = (
            f"		{ref_id} /* AppIcon-{mood}.icns */ = "
            f"{{isa = PBXFileReference; lastKnownFileType = image.icns; path = AppIcon-{mood}.icns; sourceTree = \"<group>\"; }};\n"
        )
        text = text.replace("/* End PBXFileReference section */",
                            line + "/* End PBXFileReference section */")

    return text


def main() -> None:
    force = "--force" in sys.argv
    if not PBXPROJ.exists():
        sys.exit(f"missing: {PBXPROJ}")
    original = PBXPROJ.read_text()
    BACKUP.write_text(original)
    patched = patch(original, force=force)
    if patched == original:
        print("==> no changes needed (already patched)")
    else:
        PBXPROJ.write_text(patched)
        print(f"==> patched {PBXPROJ} (backup at {BACKUP})")
    r = subprocess.run(["plutil", "-lint", str(PBXPROJ)], capture_output=True, text=True)
    print("plutil -lint:", r.stdout.strip() or r.stderr.strip())
    sys.exit(r.returncode)


if __name__ == "__main__":
    main()
