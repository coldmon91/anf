import SwiftUI

/// First-launch cheat sheet. Everything that makes anf worth using hides
/// behind a keystroke — without this card a new user sees "a sparse Finder"
/// and never finds ⌘K, 초성 검색 or the splits. Shown once; reopenable from
/// 보기 메뉴 → 단축키 한눈에 보기.
struct WelcomeOverlay: View {
    @Bindable var workspace: WorkspaceModel

    private struct Row: Identifiable {
        let id = UUID()
        let keys: String
        let text: String
    }

    private var rows: [Row] {
        [
            .init(keys: "⌘K", text: L("Search everything — names, contents, even hwpx/pdf body text", "모든 것 검색 — 파일명·내용, hwpx·pdf 본문까지")),
            .init(keys: L("type", "타이핑"), text: L("Just type to jump — Korean initial consonants work (ㄱㅊ → 경찰청)", "그냥 입력하면 점프 — 초성도 됩니다 (ㄱㅊ → 경찰청)")),
            .init(keys: "⌘1–4", text: L("Split panes — new panes open at the current folder", "창 분할 — 새 패널은 현재 폴더에서 시작")),
            .init(keys: "F5 · F6", text: L("Copy · move to the other pane", "다른 패널로 복사 · 이동")),
            .init(keys: "Space", text: L("Quick Look", "훑어보기 (Quick Look)")),
            .init(keys: "⌃`", text: L("Built-in terminal (SSH from the sidebar)", "내장 터미널 (사이드바에서 SSH 바로 접속)")),
            .init(keys: "⌘Z", text: L("Undo file operations — moves, renames, even Trash", "파일 작업 취소 — 이동·이름변경·휴지통까지 되돌리기")),
            .init(keys: "⌥⇧⌘C", text: L("Copy the current folder's path", "현재 폴더 경로 복사")),
        ]
    }

    var body: some View {
        if workspace.showWelcome {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                    .onTapGesture { dismiss() }
                VStack(alignment: .leading, spacing: 0) {
                    Text(L("Hands on the keyboard.", "손은 키보드에."))
                        .font(.system(size: 22, weight: .bold))
                    Text(L("Everything in anf is a keystroke away. The essentials:", "anf의 모든 것은 단축키 하나 거리에 있습니다. 핵심만:"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(rows) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(row.keys)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                                    .frame(minWidth: 86, alignment: .center)
                                Text(row.text).font(.system(size: 13))
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.vertical, 18)

                    HStack {
                        Text(L("Reopen anytime: View → Shortcuts at a Glance", "다시 보기: 보기 → 단축키 한눈에 보기"))
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                        Spacer()
                        Button(L("Start", "시작하기")) { dismiss() }
                            .keyboardShortcut(.defaultAction)
                            .controlSize(.large)
                    }
                }
                .padding(28)
                .frame(width: 560)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.12)))
                .shadow(radius: 40)
            }
            .transition(.opacity)
        }
    }

    private func dismiss() {
        workspace.showWelcome = false
        UserDefaults.standard.set(true, forKey: "anf.welcomed.v1")
    }
}
