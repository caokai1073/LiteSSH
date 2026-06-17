<div align="center">

<img src="assets/icon.png" width="140" alt="LiteSSH 아이콘">

# LiteSSH

**네이티브 macOS SSH 클라이언트 — 터미널, 파일 브라우저, 서버 간 전송을 하나의 창에**

[다운로드](#다운로드) · [기능](#기능) · [빠른 시작](#빠른-시작) · [아키텍처](#아키텍처) · [DMG 빌드](#dmg-빌드)

[English](README.md) · [中文](README.zh.md) · [日本語](README.ja.md) · [Français](README.fr.md) · [Español](README.es.md) · **한국어**

</div>

---

## 다운로드

[**→ 최신 릴리즈 다운로드**](https://github.com/caokai1073/LiteSSH/releases/latest)

macOS 13 Ventura 이상이 필요합니다. `.dmg`를 열고 **LiteSSH**를 응용 프로그램 폴더로 드래그하세요.

---

## 기능

| | |
|---|---|
| **완전한 터미널** | SwiftTerm 기반, 완전한 ANSI/VT100 지원 — htop, nvtop, vim 별도 설정 없이 동작 |
| **파일 브라우저** | 사이드바 드릴인 방식 탐색, 주소 표시줄, 상위 디렉토리 이동, 새 폴더 생성 지원 |
| **업로드 / 다운로드** | 로컬 파일을 드래그하여 업로드; 원격 항목을 우클릭하거나 드래그하여 다운로드 — **파일과 폴더** 모두 지원 |
| **서버 간 전송** | 여러 파일/폴더 체크 → 우클릭 → 다른 서버로 전송, 실시간 전송 진행률 표시 |
| **PEM / 개인 키 인증** | 비밀번호, 개인 키, AWS `.pem` 파일 지원. 패스프레이즈는 키체인에서 자동 제공 |
| **인증 정보 한 번만 입력** | 서버 추가 시 비밀번호 또는 패스프레이즈를 한 번 입력하면 이후 연결과 파일 작업에서 재입력 불필요 |
| **이중 언어 인터페이스** | 시스템 로케일에 따라 중국어 또는 영어로 자동 전환 |
| **다크 / 라이트 모드** | 터미널 색상이 시스템 외관에 자동으로 맞춰짐 |

---

## 빠른 시작

순수 **Swift Package** 프로젝트로 `.xcodeproj`가 필요하지 않습니다.

```
1. Xcode에서 Package.swift 열기
2. 의존성 해결 대기 (SwiftTerm — github.com 접근 필요)
3. 스킴에서 "LiteSSH" 선택 → ▶ 실행
4. "+"를 클릭하여 서버 추가 — 호스트, 포트, 사용자명, 인증 정보를 한 번만 입력
```

---

## 아키텍처

LiteSSH는 SSH 프로토콜을 직접 구현하지 않고, macOS에 내장된 OpenSSH(`/usr/bin/ssh`, `/usr/bin/sftp`)에 위임합니다.

**연결 재사용.** 첫 번째 연결이 ControlMaster가 됩니다. 이후의 모든 파일 작업은 동일한 ControlPath 소켓을 공유하므로 재인증이 필요하지 않습니다.

**인증 정보 보안.** 비밀번호와 패스프레이즈는 macOS 키체인에 저장됩니다. 실행 시 `AskPassHelper`가 임시 `SSH_ASKPASS` 스크립트를 제공하여 ssh/sftp 서브프로세스가 환경 변수를 통해 비밀번호를 비대화형으로 가져옵니다. 프로세스 인수에는 평문 비밀번호가 노출되지 않습니다.

**파일 전송.** 공백이 포함된 경로의 파싱 문제를 방지하기 위해 scp 대신 `sftp -b <batchfile>`을 사용합니다. 디렉토리 재귀 전송은 `get -r` / `put -r`을 사용하며, 서버 간 전송은 로컬 임시 디렉토리를 경유합니다.

**파이프 안전성.** 프로세스 실행 중 stdout과 stderr 파이프를 `readabilityHandler`로 동시에 읽어 64 KB 파이프 버퍼가 가득 찼을 때 발생하는 데드락을 방지합니다.

---

## 프로젝트 구조

```
Sources/LiteSSH/
├── Models/
│   ├── ServerProfile.swift          # 서버 설정 모델
│   └── RemoteFile.swift             # 원격 파일 항목
├── Services/
│   ├── SSHConnection.swift          # 연결 핵심 + ControlMaster 관리
│   ├── ProcessRunner.swift          # 서브프로세스 래퍼 (동시 파이프 읽기)
│   ├── ProfileStore.swift           # 설정 영속화
│   ├── KeychainHelper.swift         # 키체인 읽기 / 쓰기
│   └── AskPassHelper.swift          # SSH_ASKPASS 비대화형 인증 정보 제공
├── ViewModels/
│   ├── SessionStore.swift           # Profile → SSHConnection 매핑
│   └── FileBrowserStore.swift       # 파일 브라우저 상태 (경로 + 뒤로 가기 스택)
├── Views/
│   ├── Sidebar/
│   │   ├── ServerListView.swift     # 사이드바: 서버 목록 + 파일 브라우저 열
│   │   └── ServerEditView.swift     # 서버 추가 / 편집 폼
│   ├── Terminal/
│   │   ├── TerminalContainerView.swift
│   │   └── TerminalViewRegistry.swift
│   ├── Files/
│   │   └── CrossTransferSheet.swift # 서버 간 전송 UI
│   ├── DetailView.swift
│   └── ContentView.swift
├── Localization.swift               # L10n.s(중국어, 영어)
└── LiteSSHApp.swift                 # @main 진입점 + AppDelegate
```

---

## DMG 빌드

```bash
cd "SSH tool/LiteSSH"
chmod +x build_dmg.sh
./build_dmg.sh
```

프로젝트 루트에 `LiteSSH-1.0.dmg`와 `LiteSSH.app`이 생성됩니다. 스크립트는 릴리스 바이너리 컴파일, 앱 아이콘 생성, 애드혹 서명, Applications 심볼릭 링크가 포함된 DMG 패키징을 수행합니다. 다른 기기에 배포하려면 애드혹 서명을 Developer ID 인증서 서명으로 교체하세요.

---

## 의존성

| 의존성 | 버전 | 역할 |
|---|---|---|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | ≥ 1.0 | 터미널 에뮬레이터 |
| macOS OpenSSH | 내장 | SSH / SFTP 프로토콜 |
| macOS Keychain | 내장 | 인증 정보 안전 저장 |

**시스템 요구 사항:** macOS 13 Ventura 이상 · Xcode 15+ (개발 시에만 필요)

---

## 라이선스

Apache 2.0
