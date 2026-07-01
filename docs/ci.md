# CI / Release workflow (GitHub Actions)

> AGENTS.md 把项目级 Codex 准则留作主入口, GitHub/CI 基础设施细节放这里. 改 `.github/workflows/*.yml` 时先看本文件再改.

## 1. test.yml — PR CI

`.github/workflows/test.yml` — PR 合并到 `main` 时跑 (`pull_request: [main]` types: opened/synchronize/reopened/closed):

1. **macOS 15 runner** + **Xcode 16** (用具体版本避免 macos-latest 默认变化导致 build 飘, 工程 deployment target 26.0 需要 Xcode 16 的 macOS 26 SDK)
2. **Build (Debug)** — `xcodebuild build-for-testing` (不 launch .app, CI 不需要图形界面), 命令行加 `CODE_SIGN_IDENTITY=""` + `CODE_SIGNING_REQUIRED=NO` + `CODE_SIGNING_ALLOWED=NO` 跳过签名 (CI runner 缺 Mac Development cert), `MACOSX_DEPLOYMENT_TARGET=15.0` 降 target 让 macos-15 runner 能跑 (release build 仍走 26.0)
3. **Run Tests** — `./scripts/run_tests.sh` (`MACOSX_DEPLOYMENT_TARGET=15.0` + `SKIP_SIGNING=1` 两个 env var 让脚本跟 build step 行为对齐)
4. **失败时上传 xcresult artifact** — 本地能用 `xcodebuild -resultBundlePath` 看 detail

**触发策略** (Phase 15 改):
- ✅ **跑**: PR open / synchronize (新 commit push 到 PR) / reopened / **closed (= 合并到 main)**
- ❌ **不跑**: direct push 到 main (如 `git push origin main` 不开 PR)
- ❌ **不跑**: feature branch push 不开 PR
- ❌ **不跑**: tag push (走 release.yml)

**设计意图**: "代码合并到 main 之后才触发 CI" — 保证 main 永远 build 通过, 但不在 direct push 时空跑 (开发期间用本地 `./scripts/run_tests.sh` 验证即可). release tag 触发 release.yml 不受此限制.

**Cache**: `build/DerivedData` 走 `actions/cache@v4`, key 用 `hashFiles('*.xcodeproj/project.pbxproj')` (pbxproj 改了缓存失效, 缓存命中能省 1-2 分钟).

**Concurrency**: `missingpp-${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}` + `cancel-in-progress: true` — 同一 PR 不并发跑 (新 commit 取消旧 run), 节省 macOS runner quota. `pull_request.number || github.ref` 兼容 PR 跟 tag 两种 trigger 来源.

### 不要做

- 不要用 `macos-latest` — 默认 Xcode 版本会变, 工程 build 飘时排查很痛
- 不要在 workflow 里写 `sudo xcodebuild` — GitHub Actions runner 已经在 root 下, xcodebuild 直接调
- 不要传 secret 给 `run:` 命令 — secret 会出现在 log 里. 用 env 变量
- 不要 `actions/upload-artifact` 上传 `build/DerivedData/Build/Products/Debug/MissingPlusPlus.app` — 整个 .app 几十 MB, 没必要

## 2. release.yml — DMG 发布

`.github/workflows/release.yml` — tag push 或 manual dispatch 触发, 跑 `build-dmg.sh` 出 DMG + 上传 GitHub Release (**draft**, 用户手动 review + publish).

**Triggers**:
- `push: tags: ['v*.*.*']` — `git tag v1.2.3 && git push origin v1.2.3` 自动跑
- `workflow_dispatch: inputs.version` — GitHub Actions 页面点 "Run workflow", 输入 version 字符串 (e.g. `1.2.3`)

**Steps**:
1. checkout (`fetch-depth: 0`, git describe 需要全部 history)
2. select Xcode 15.4
3. cache DerivedData (key = `hashFiles('*.xcodeproj/project.pbxproj')`)
4. **Resolve version** — tag push 取 `GITHUB_REF_NAME` 去掉 `v` 前缀; dispatch 取 `inputs.version`
5. **Build DMG** — `VERSION=$version ./scripts/build-dmg.sh`
6. **Verify DMG** — 验证 `dist/MissingPlusPlus-$VERSION.dmg` 存在 + `shasum -a 256`
7. **Read CFBundleVersion** — 用 `PlistBuddy` 读 `CFBundleShortVersionString` + `CFBundleVersion`, **校验** tag 版本必须 == `CFBundleShortVersionString` (防止 release v1.2.0 但 app 实际是 1.0.0 的错位)
8. **Create GitHub Release** — `softprops/action-gh-release@v2`, `files: dist/*.dmg`, `draft: true`, `generate_release_notes: true` (从 merged PRs 自动生成 notes)

**Permissions**: `contents: write` (创建 Release 需要)

**Concurrency**: `group: missingpp-release-${{ github.ref }}` + `cancel-in-progress: false` (release 不能中途取消, serialize 跑)

### `build-dmg.sh` 的 VERSION 支持 (小幅 refactor)

- 旧: `DMG_NAME="MissingPlusPlus-1.0.dmg"` (硬编码)
- 新: `VERSION="${VERSION:-1.0}"` + `DMG_NAME="MissingPlusPlus-${VERSION}.dmg"`
- 向后兼容: 本地 `bash scripts/build-dmg.sh` 仍然出 `MissingPlusPlus-1.0.dmg`
- CI: `VERSION=${{ steps.version.outputs.version }} ./scripts/build-dmg.sh` → `MissingPlusPlus-$VERSION.dmg`

### 签名限制

workflow 当前出 **ad-hoc 签名** 的 DMG (仅本地用). 正式分发需要:
- 加入 Apple Developer Program ($99/年)
- 签发 `Developer ID Application` 证书
- `xcrun notarytool store-credentials <profile>` 存到 keychain
- workflow 加 `DEVELOPER_ID=1` + `DEVELOPMENT_TEAM=<TEAMID>` + `NOTARY_PROFILE` 3 个 GitHub secret
- 然后 `xcrun notarytool submit + staple` 跑公证

当前 workflow 没设这 3 个 secret, 所以默认 ad-hoc. 详见 AGENTS.md §7 + §9.

### 不要做

- 不要把 `Developer ID` 证书 / notary profile 直接 commit 到 repo (用 GitHub secret)
- 不要 `cancel-in-progress: true` — release 跑到一半被取消会留下半截 DMG
- 不要在 release workflow 里跑 `git push --force` — 万一 build 出问题, tag 已经被 force push 了
- 不要在 release notes 里写敏感信息 (API key / 测试 token) — release 是公开的
- 不要用 `softprops/action-gh-release@v1` — 旧版, v2 才是当前支持的

### 推 GitHub 后第一次 release 的检查清单

1. `git tag v1.0.1 && git push origin v1.0.1` (或者 Actions 页面手动 dispatch)
2. workflow 跑完后到 Releases 页面, 应该看到 draft release
3. 检查 draft release 的 notes + DMG 文件 + SHA256
4. 点 "Publish release" 公开

### Update Checker publish 步骤 (v0.0.2+)

`release.yml` 创建的是 **draft release**,GitHub API `/releases/latest` **不会**返回 draft,所以 update checker 看不到新版本。**每次发布后必须手动 Publish release**:

1. 完成上面 "推 GitHub 后第一次 release 的检查清单"
2. GitHub Releases 页面打开 draft,点 "Publish release" 公开
3. Publish 完几分钟后,用旧版 app (e.g. v0.0.1) 跑一次,启动 5s 后主窗口顶部应该出 "新版本 v0.0.2 可用" banner

详细见 AGENTS.md §25。

## 3. 未来可能加的 workflow

- `lint.yml` — SwiftLint / swift-format check (如果未来引入 lint)
