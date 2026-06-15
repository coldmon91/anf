#!/bin/bash
# One-command release: bump version → build → notarize → zip → GitHub release → cask update.
#   ./tools/release.sh 1.1.0
# Requires: gh (authenticated), push access to rescenedev/anf and
# rescenedev/homebrew-anf, a "Developer ID Application" cert in the keychain,
# and a notarytool credential profile named "anf-notary" (set up once with:
#   xcrun notarytool store-credentials anf-notary \
#       --key AuthKey_XXXX.p8 --key-id XXXX --issuer XXXX-...).
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARY_PROFILE="anf-notary"

VERSION="${1:?사용법: ./tools/release.sh <version>  (예: 1.1.0)}"
TAG="v$VERSION"

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "✗ 커밋되지 않은 변경이 있습니다. 먼저 커밋하세요." >&2
    exit 1
fi

# Preflight: fail early (before bumping version / building) if signing or
# notarization isn't set up, so a release never ships unsigned by accident.
if ! security find-identity -p codesigning -v 2>/dev/null | grep -q "Developer ID Application"; then
    echo "✗ 'Developer ID Application' 인증서가 키체인에 없습니다." >&2
    echo "  Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application" >&2
    exit 1
fi
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "✗ notarytool 자격증명 프로파일 '$NOTARY_PROFILE' 가 없습니다." >&2
    echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --key AuthKey_XXXX.p8 --key-id XXXX --issuer XXXX-..." >&2
    exit 1
fi

echo "▸ Info.plist 버전 → $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" Resources/Info.plist

echo "▸ 테스트"
swift run anfTests

echo "▸ 빌드"
./build.sh

echo "▸ 공증 (notarytool submit --wait)"
rm -f anf-notarize.zip
ditto -c -k --keepParent anf.app anf-notarize.zip
xcrun notarytool submit anf-notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
rm -f anf-notarize.zip
echo "▸ 티켓 스테이플"
xcrun stapler staple anf.app
xcrun stapler validate anf.app
spctl -a -vvv anf.app   # 'accepted, source=Notarized Developer ID' 이어야 정상

echo "▸ zip (스테이플된 앱)"
rm -f anf.zip
ditto -c -k --keepParent anf.app anf.zip
SHA=$(shasum -a 256 anf.zip | awk '{print $1}')
echo "  sha256: $SHA"

echo "▸ 버전 커밋 + 태그"
git add Resources/Info.plist
git commit -m "release: $TAG"
git tag "$TAG"
git push origin main "$TAG"

echo "▸ GitHub Release $TAG"
gh release create "$TAG" anf.zip --repo rescenedev/anf \
    --title "anf $TAG" --generate-notes

echo "▸ Homebrew cask 갱신"
TAP_DIR=$(mktemp -d)
git clone -q --depth 1 https://github.com/rescenedev/homebrew-anf "$TAP_DIR"
sed -i '' "s/version \"[^\"]*\"/version \"$VERSION\"/" "$TAP_DIR/Casks/anf.rb"
sed -i '' "s/sha256 \"[^\"]*\"/sha256 \"$SHA\"/" "$TAP_DIR/Casks/anf.rb"
git -C "$TAP_DIR" commit -aqm "anf $VERSION"
git -C "$TAP_DIR" push -q
rm -rf "$TAP_DIR" anf.zip

echo "✓ $TAG 릴리즈 완료 — brew upgrade --cask anf 로 받아집니다"
