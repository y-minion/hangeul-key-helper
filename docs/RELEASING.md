# 공개 배포 준비

GitHub 저장소 없이도 로컬 앱을 빌드하고 사용할 수 있습니다. 저장소를 만들 때는 빈 저장소로 만든 뒤 이 프로젝트를 올리면 됩니다. 서명 인증서나 공증 자격 증명은 절대 저장소에 넣지 않습니다.

## 1. 제품 식별자와 버전

현재 앱/LaunchAgent 식별자는 `app.hangeulkey.helper`, 버전은 0.1.0입니다. 최초 공개 배포 전에 실제 개발자가 관리할 식별자로 정하고 Sources/KeyCore/Installation.swift, InstallPaths.agent, scripts/build.sh를 함께 변경하세요. 식별자 변경은 이미 설치된 사용자의 이전/삭제 처리가 필요하므로 배포 후 임의로 바꾸지 않습니다.

## 2. Developer ID로 서명

Apple Developer Program의 Developer ID Application 인증서를 사용합니다. Keychain에 인증서와 개인 키가 설치된 Mac에서 실행하세요.

```sh
SIGNING_IDENTITY='Developer ID Application: 실제 인증서 이름 (TEAMID)' ./scripts/build.sh
```

로컬 테스트 빌드와 공식 배포 빌드는 구분해서 표시합니다. resources/사용안내.html의 ‘개발용 임시 서명’ 문구도 실제 배포 상태에 맞게 수정한 뒤 다시 빌드하세요.

## 3. 공증

미리 Keychain에 저장한 notarytool 프로파일을 사용합니다. 비밀번호를 스크립트나 저장소에 저장하지 마세요.

```sh
xcrun notarytool submit dist/HangeulKeyHelper-0.1.0-macOS.zip --keychain-profile 실제프로파일이름 --wait
xcrun stapler staple 'dist/한영키 도우미.app'
xcrun stapler validate 'dist/한영키 도우미.app'
codesign --verify --deep --strict 'dist/한영키 도우미.app'
spctl --assess --type execute --verbose 'dist/한영키 도우미.app'
```

공증이 Accepted인지 확인한 뒤, 티켓이 첨부된 앱을 새 ZIP으로 패키징하고 체크섬을 다시 생성합니다. 기존 ZIP에 업데이트하는 대신 새 파일 이름으로 만듭니다.

```sh
ditto -c -k --sequesterRsrc --keepParent 'dist/한영키 도우미.app' dist/HangeulKeyHelper-0.1.0-notarized-macOS.zip
shasum -a 256 dist/HangeulKeyHelper-0.1.0-notarized-macOS.zip > dist/SHA256SUMS-notarized
```

## 4. GitHub Release

README의 수동 테스트를 수행한 후, 코드 저장소에 버전 태그를 만들고 GitHub Release에 공증 ZIP과 체크섬을 첨부합니다. 확인한 macOS 버전과 하드웨어, 알려진 제한을 릴리스 노트에 적습니다. 최초 다운로드/격리 속성이 있는 다른 Mac에서 실제로 실행되는지 검증하세요.

이 프로젝트는 GitHub 저장소 생성, push, 공개 Release 업로드를 자동 수행하지 않습니다. 소유자의 저장소 URL과 배포 의사가 정해진 뒤 연결합니다.
