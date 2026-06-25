#!/usr/bin/env bash
# Sparkle scaffolding for Missing++.
#
# This script does NOT actually integrate Sparkle (it requires the user to
# sign up for a Sparkle account, host an appcast feed, and resolve several
# signing-related choices). What it does:
#   1. Verifies Sparkle prerequisites are present on the system.
#   2. Documents what needs to happen for real integration.
#   3. Generates a local appcast.xml template you can hand-edit and upload.
#
# To actually turn on Sparkle:
#   * `brew install sparkle` (gets you the `generate_appcast` tool, but the
#     real Sparkle framework still needs to be vendored into the project).
#   * Drop Sparkle.framework into MissingPlusPlus/Frameworks/ (or use SPM).
#   * Add Info.plist keys (see `add_sparkle_info_plist_keys` below).
#   * Host the appcast.xml on a URL the app can reach.
#   * Sign updates with `generate_appcast` and EdDSA.
#
# The check below is just a smoke test that the user has the right tools.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Sparkle prerequisites check"

missing=0

if xcodebuild -version >/dev/null 2>&1; then
    echo "  ok  xcodebuild found"
else
    echo "  MISS  xcodebuild not in PATH"; missing=1
fi

if command -v brew >/dev/null 2>&1; then
    echo "  ok  brew found (you can: brew install sparkle)"
else
    echo "  warn  brew not installed (you'll need to install Sparkle manually)"
fi

if command -v generate_appcast >/dev/null 2>&1; then
    echo "  ok  generate_appcast found"
else
    echo "  warn  generate_appcast not installed; install via: brew install sparkle"
fi

if command -v sign_update >/dev/null 2>&1; then
    echo "  ok  sign_update found (Sparkle EdDSA tool)"
else
    echo "  warn  sign_update not installed; install via: brew install sparkle"
fi

echo
echo "==> appcast.xml template (edit and host on your update server)"
mkdir -p "$PROJECT_DIR/dist"
APPCAST="$PROJECT_DIR/dist/appcast.xml.template"
cat > "$APPCAST" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Missing++ Changelog</title>
    <link>https://your-domain.example/missingpp/appcast.xml</link>
    <description>Most recent changes for Missing++.</description>
    <language>zh-CN</language>
    <item>
      <title>Missing++ 1.0</title>
      <sparkle:version>1</sparkle:version>
      <sparkle:shortVersionString>1.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <pubDate>Tue, 25 Jun 2026 14:00:00 +0800</pubDate>
      <description><![CDATA[
        <h2>1.0</h2>
        <ul>
          <li>5 个 mood 彩色菜单栏图标 + 30 天统计 trend chart</li>
          <li>记录通知 + 搜索 + 替代 App Icon (bundle 内)</li>
          <li>Developer ID 模式脚手架 (build-dmg.sh DEVELOPER_ID=1)</li>
        </ul>
      ]]></description>
      <enclosure
          url="https://your-domain.example/missingpp/MissingPlusPlus-1.0.dmg"
          length="0"
          type="application/octet-stream"
          sparkle:edSignature="REPLACE_WITH_EDDSA_SIGNATURE" />
    </item>
  </channel>
</rss>
XML
echo "  wrote $APPCAST"

echo
echo "==> Info.plist keys Sparkle needs (add to MissingPlusPlus/Info.plist)"
cat <<'PLIST'
    <key>SUFeedURL</key>
    <string>https://your-domain.example/missingpp/appcast.xml</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUPublicEDKey</key>
    <string>REPLACE_WITH_YOUR_EDDSA_PUBLIC_KEY</string>
PLIST

echo
echo "==> Next steps"
echo "  1. Sign up for a Sparkle account (https://sparkle-project.org/) and read"
echo "     the security guide. Sparkle 2 uses EdDSA; you need to generate a keypair"
echo "     with generate_keys (part of the Sparkle tools)."
echo "  2. Vendor Sparkle.framework (download from the GitHub release) into"
echo "     MissingPlusPlus/Frameworks/ and add it to the Xcode target."
echo "  3. Wire SPUUpdater into the AppDelegate (one-line checkForUpdates call"
echo "     from the overflow menu). The actual integration is too project-specific"
echo "     to script here."
echo "  4. Host the appcast.xml on a URL your users can reach (GitHub Pages,"
echo "     Netlify, S3, whatever). Re-run 'generate_appcast dist/' to sign new"
echo "     entries and update the file."
echo
echo "  Until you complete those steps, this scaffold is informational only."
exit $missing
