#!/bin/bash
# 打一个可分发的版本：构建 → 签名 → 打 DMG → 公证 → 装订 → 验证。
#
# 用法：
#   ./scripts/release.sh              # 完整流程
#   ./scripts/release.sh --check      # 只做前置检查，不构建
#   ./scripts/release.sh --skip-notarize   # 本地试跑，跳过公证（产物不可分发）
#
# 首次使用前需要两样东西，见 --check 的输出。
set -euo pipefail
cd "$(dirname "$0")/.."

readonly TEAM_ID="B38RD53WGZ"
readonly APP_NAME="驭Git"
readonly SCHEME="Yugit"
readonly BUNDLE_ID="com.chenya.yugit"
# 公证凭据在钥匙串里的名字。脚本全程不接触密码本身。
readonly KEYCHAIN_PROFILE="${YUGIT_NOTARY_PROFILE:-yugit-notary}"

readonly BUILD_DIR="build/release"
readonly ARCHIVE="$BUILD_DIR/$SCHEME.xcarchive"
readonly EXPORT_DIR="$BUILD_DIR/export"

# ── 输出 ──────────────────────────────────────────────────────────
step() { printf '\n\033[1;34m▸ %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
die()  { printf '\n\033[1;31m✗ %s\033[0m\n' "$1" >&2; exit 1; }

SKIP_NOTARIZE=false
CHECK_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=true ;;
        --skip-notarize) SKIP_NOTARIZE=true ;;
        *) die "未知参数：$arg" ;;
    esac
done

# ── 前置检查 ──────────────────────────────────────────────────────
#
# 全部检查一遍再决定要不要继续，而不是遇到第一个问题就退出。
# 缺两样东西时，一次说清比让人来回跑两趟强。
step "前置检查"

MISSING=0

# 1. Developer ID 证书
#
# 注意不能用 Apple Distribution 顶替：那张是上 App Store 用的。
# 在 App Store 之外分发必须是 Developer ID Application，
# 两者由不同的根证书签发，Gatekeeper 认的也不是同一条链。
SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 \
    | sed 's/.*"\(.*\)".*/\1/') || true

if [ -z "${SIGN_IDENTITY:-}" ]; then
    warn "找不到 Developer ID Application 证书"
    cat <<EOF

    这是在 App Store 之外分发唯一能用的证书。创建方式（二选一）：

    A. Xcode 里创建（推荐，最省事）
       Xcode → Settings → Accounts → 选中账号 → Manage Certificates
       → 左下角 + → Developer ID Application

    B. 网页创建
       https://developer.apple.com/account/resources/certificates/add
       选 Developer ID Application，按提示上传 CSR

    注意：个人账号可以直接创建；组织账号只有 Account Holder 有权限。
    另外每个团队的 Developer ID 证书数量有上限，别反复创建。

EOF
    MISSING=$((MISSING + 1))
else
    ok "签名证书：$SIGN_IDENTITY"
fi

# 2. 公证凭据
if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
    warn "公证凭据 '$KEYCHAIN_PROFILE' 未配置"
    cat <<EOF

    公证需要一次性把凭据存进钥匙串。推荐用 App Store Connect API Key，
    它比 Apple ID + 专用密码更安全，也不会因为改密码而失效：

       xcrun notarytool store-credentials "$KEYCHAIN_PROFILE" \\
           --key /path/to/AuthKey_XXXXX.p8 \\
           --key-id <KEY_ID> \\
           --issuer <ISSUER_UUID>

    API Key 在这里创建（需要 Account Holder 权限）：
       https://appstoreconnect.apple.com/access/integrations/api

    或者用 Apple ID（简单但要专用密码，且改密码后失效）：

       xcrun notarytool store-credentials "$KEYCHAIN_PROFILE" \\
           --apple-id <你的 Apple ID> \\
           --team-id $TEAM_ID \\
           --password <应用专用密码>

    专用密码在 https://appleid.apple.com 的「登录与安全」里生成。

EOF
    MISSING=$((MISSING + 1))
else
    ok "公证凭据：$KEYCHAIN_PROFILE"
fi

# 3. 工作区状态
if [ -n "$(git status --porcelain)" ]; then
    warn "工作区有未提交的改动——发布版本应当来自干净的提交"
else
    ok "工作区干净"
fi

# 直接从工程文件读。这个项目用 Xcode 自动生成 Info.plist，
# 没有独立的 plist 文件可查，PlistBuddy 那条路走不通。
VERSION=$(grep -m1 'MARKETING_VERSION' Yugit.xcodeproj/project.pbxproj \
    | sed 's/.*= *//;s/;//' | tr -d ' ')
BUILD_NUMBER=$(grep -m1 'CURRENT_PROJECT_VERSION' Yugit.xcodeproj/project.pbxproj \
    | sed 's/.*= *//;s/;//' | tr -d ' ')
[ -n "$VERSION" ] || die "读不到版本号"
ok "版本：$VERSION (build $BUILD_NUMBER)"

# tag 与版本号必须对得上。对不上通常意味着忘了升版本号就打包，
# 那样发出去两个不同的构建会自称同一个版本，用户报 bug 时无法定位。
CURRENT_TAG=$(git describe --exact-match --tags 2>/dev/null || echo "")
if [ -n "$CURRENT_TAG" ] && [ "$CURRENT_TAG" != "v$VERSION" ]; then
    warn "当前 tag 是 $CURRENT_TAG，但版本号是 $VERSION，两者不一致"
elif [ -z "$CURRENT_TAG" ]; then
    warn "当前提交没有 tag——正式发布前应当先打 tag"
fi

if [ "$CHECK_ONLY" = true ]; then
    [ "$MISSING" -gt 0 ] && die "还缺 $MISSING 项，见上面的说明"
    ok "全部就绪，可以执行 ./scripts/release.sh"
    exit 0
fi
[ "$MISSING" -gt 0 ] && die "还缺 $MISSING 项，见上面的说明"

readonly DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
readonly APP_PATH="$EXPORT_DIR/$APP_NAME.app"

# ── 测试 ──────────────────────────────────────────────────────────
step "跑测试"
for pkg in GitKit AIKit ForgeKit; do
    (cd "Packages/$pkg" && swift test >/dev/null 2>&1) \
        || die "$pkg 测试未通过，发布中止"
done
ok "全部通过"

# ── 构建 ──────────────────────────────────────────────────────────
step "构建 Release"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild archive \
    -project Yugit.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -destination 'generic/platform=macOS' \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
    >"$BUILD_DIR/archive.log" 2>&1 || {
        tail -30 "$BUILD_DIR/archive.log"
        die "构建失败，完整日志见 $BUILD_DIR/archive.log"
    }
ok "已归档"

# 导出配置。
# 用 developer-id 而不是 mac-application：后者产出的包只能在本机跑。
cat >"$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Developer ID Application</string>
    <!-- 交给 Apple 重签会丢掉我们指定的 timestamp 与 runtime 选项 -->
    <key>destination</key><string>export</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    >"$BUILD_DIR/export.log" 2>&1 || {
        tail -30 "$BUILD_DIR/export.log"
        die "导出失败，完整日志见 $BUILD_DIR/export.log"
    }
[ -d "$APP_PATH" ] || die "导出后找不到 $APP_PATH"
ok "已导出"

# ── 验证签名 ──────────────────────────────────────────────────────
#
# 在打包之前验证。签错了的话，公证会在几分钟后才告诉你，
# 而这里几秒就能发现。
step "验证签名"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1 \
    | grep -q "satisfies its Designated Requirement" \
    || die "签名验证未通过"
ok "签名有效"

codesign -d --verbose=4 "$APP_PATH" 2>&1 | grep -q "flags=.*runtime" \
    || die "硬化运行时（hardened runtime）未启用——公证会被拒"
ok "硬化运行时已启用"

# ── 打 DMG ────────────────────────────────────────────────────────
step "打包 DMG"
STAGING=$(mktemp -d)
cp -R "$APP_PATH" "$STAGING/"
# 拖拽安装的惯例：给一个指向 /Applications 的替身
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" \
    -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$STAGING"
ok "$(basename "$DMG_PATH") （$(du -h "$DMG_PATH" | cut -f1)）"

# DMG 本身也要签名，否则用户下载后仍会被 Gatekeeper 拦
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
ok "DMG 已签名"

# ── 公证 ──────────────────────────────────────────────────────────
if [ "$SKIP_NOTARIZE" = true ]; then
    warn "已跳过公证——这个产物只能自己用，别人下载会被 Gatekeeper 拦下"
    exit 0
fi

step "提交公证（通常 1–5 分钟）"
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait 2>&1 | tee "$BUILD_DIR/notarize.log" | grep -E "id:|status:" || true

grep -q "status: Accepted" "$BUILD_DIR/notarize.log" || {
    # 被拒时把原因拉出来。Apple 的拒绝理由藏在单独的日志里，
    # 不主动取的话只会看到一句 "Invalid"，没有任何可操作信息。
    SUBMISSION_ID=$(grep -m1 "id:" "$BUILD_DIR/notarize.log" | awk '{print $2}')
    if [ -n "${SUBMISSION_ID:-}" ]; then
        printf '\n公证被拒，详细原因：\n'
        xcrun notarytool log "$SUBMISSION_ID" \
            --keychain-profile "$KEYCHAIN_PROFILE" 2>&1 | head -40
    fi
    die "公证未通过"
}
ok "公证通过"

# ── 装订 ──────────────────────────────────────────────────────────
#
# 把公证票据钉进 DMG。不做这一步的话，用户首次打开时
# 需要联网向 Apple 查询——离线环境下会被拦。
step "装订公证票据"
xcrun stapler staple "$DMG_PATH" >/dev/null
ok "已装订"

# ── 最终验证 ──────────────────────────────────────────────────────
#
# 用 Gatekeeper 自己的工具验，而不是相信前面几步都成功了。
# 这一步模拟的正是用户双击时系统做的判断。
step "最终验证"
xcrun stapler validate "$DMG_PATH" >/dev/null && ok "票据有效"

hdiutil attach "$DMG_PATH" -nobrowse -quiet -mountpoint /tmp/yugit-verify
spctl -a -vv "/tmp/yugit-verify/$APP_NAME.app" 2>&1 | grep -q "accepted" \
    && ok "Gatekeeper 放行" \
    || { hdiutil detach /tmp/yugit-verify -quiet; die "Gatekeeper 拒绝"; }
hdiutil detach /tmp/yugit-verify -quiet

printf '\n\033[1;32m完成\033[0m  %s\n' "$DMG_PATH"
printf '这个包可以直接分发，用户双击不会看到任何安全警告。\n\n'
