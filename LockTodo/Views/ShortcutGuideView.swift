import SwiftUI
import UIKit
import AppIntents

struct ShortcutGuideView: View {
    @Environment(\.openURL) private var openURL
    @State private var copiedSetupPath = false
    @State private var copiedSmartExample = false

    var body: some View {
        List {
            // One-tap setup up top: the app already registers its shortcuts, so
            // the user just opens them and adds — no building a shortcut by hand.
            Section {
                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)

                SiriTipView(intent: SmartAddTaskIntent())
                    .siriTipViewStyle(.automatic)

                SiriTipView(intent: AddTaskIntent())
                    .siriTipViewStyle(.automatic)
            } header: {
                Text("바로 설정 · 원탭")
            } footer: {
                Text("‘단축어’를 누르면 LockTodo가 미리 만들어 둔 단축어가 그대로 나옵니다. 직접 만들 필요 없이, 원하는 걸 눌러 추가하거나 Action Button·뒷면 탭·Siri에 바로 연결하세요.")
            }

            Section("빠른 작성 연결") {
                Button {
                    openURL(ShortcutService.addTaskURL)
                } label: {
                    Label("앱 입력 화면 열기 테스트", systemImage: "plus.circle")
                }

                Button {
                    if let url = URL(string: "shortcuts://") {
                        openURL(url)
                    }
                } label: {
                    Label("단축어 앱 열기", systemImage: "app.badge")
                }

                Button {
                    UIPasteboard.general.string = "내일 오후 3시 병원 예약 ! #건강 색상:파랑"
                    copiedSmartExample = true
                } label: {
                    Label(copiedSmartExample ? "스마트 입력 예시 복사됨" : "스마트 입력 예시 복사", systemImage: copiedSmartExample ? "checkmark.circle" : "doc.on.doc")
                }

                Button {
                    openURL(ShortcutService.mapURL)
                } label: {
                    Label("지도 할 일 화면 열기 테스트", systemImage: "map")
                }

                Button {
                    UIPasteboard.general.string = "설정 > 손쉬운 사용 > 터치 > 뒷면 탭 > 이중 탭 또는 삼중 탭 > 단축어 > LockTodo 새 할 일 추가"
                    copiedSetupPath = true
                } label: {
                    Label(copiedSetupPath ? "뒷면 탭 경로 복사됨" : "뒷면 탭 설정 경로 복사", systemImage: copiedSetupPath ? "checkmark.circle" : "doc.on.doc")
                }

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label("LockTodo 앱 설정 열기", systemImage: "gearshape")
                }
            }

            Section("앱에서 자동으로 못 켜는 이유") {
                Text("iOS는 앱이 손쉬운 사용, 뒷면 탭, Action Button, 전원/볼륨 버튼 동작을 직접 변경하지 못하게 막습니다. LockTodo는 대신 ‘새 할 일 추가’ App Shortcut을 제공하며, 이 단축어는 제목을 받으면 앱을 열지 않고 오늘 할 일에 바로 저장합니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            Section("새로 추가된 단축어 액션") {
                GuideRow(index: 1, text: "LockTodo 스마트 입력: “내일 오후 3시 병원 ! #건강 색상:파랑”처럼 말하면 날짜, 시간, 중요 표시, 태그, 색상을 자동 해석합니다.")
                GuideRow(index: 2, text: "LockTodo 스마트 플랜 시작: 오늘 해야 할 일 중 우선순위가 높은 항목을 골라 잠금화면 카드에 고정합니다.")
                GuideRow(index: 3, text: "LockTodo 잠금화면 순찰: 단축어 자동화에서 Live Activity 순찰 카드를 켜거나 끕니다.")
                GuideRow(index: 4, text: "LockTodo 오늘 할 일 목록 및 체크: 단축어 팝업 안에서 목록을 보고 바로 체크할 수 있습니다.")
            }

            Section("Action Button") {
                GuideRow(index: 1, text: "설정 앱을 엽니다.")
                GuideRow(index: 2, text: "동작 버튼을 선택합니다.")
                GuideRow(index: 3, text: "단축어를 선택합니다.")
                GuideRow(index: 4, text: "빠르게 제목만 넣고 싶으면 LockTodo 새 할 일 추가, 날짜/시간/태그까지 한 번에 넣고 싶으면 LockTodo 스마트 입력을 선택합니다.")
                GuideRow(index: 5, text: "동작 버튼을 누르면 시스템 입력창 또는 음성 입력으로 받은 내용이 앱을 열지 않고 저장됩니다.")
            }

            Section("잠금화면에서 앱 없이 입력") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Apple 정책상 가능한 정식 방식")
                        .font(.subheadline.weight(.semibold))
                    Text("LockTodo의 ‘새 할 일 추가’ App Intent는 잠긴 상태에서도 실행 가능한 alwaysAllowed 동작으로 구성했습니다. Siri, 단축어, Action Button은 Apple 시스템 입력창이나 음성 입력으로 제목을 받아 앱을 열지 않고 저장할 수 있습니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("불가능한 방식")
                        .font(.subheadline.weight(.semibold))
                    Text("iOS는 잠금화면 위젯, Live Activity, 하단 컨트롤에 서드파티 앱의 텍스트필드와 키보드를 허용하지 않습니다. LockTodo가 직접 입력창을 내려오게 만드는 공개 API나 App Store용 entitlement는 없습니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                GuideRow(index: 1, text: "앱을 열지 않고 저장하려면 Siri에게 “LockTodo에 할 일 추가”라고 말합니다.")
                GuideRow(index: 2, text: "Siri가 묻는 시스템 입력창 또는 음성 답변에 할 일을 입력합니다.")
                GuideRow(index: 3, text: "Action Button 또는 뒷면 탭에는 ‘LockTodo 새 할 일 추가’ 단축어를 연결합니다.")
                GuideRow(index: 4, text: "잠금화면 하단 LockTodo 컨트롤은 입력창을 띄우지 못하고 앱의 Add Task 화면을 여는 역할만 합니다.")
            }

            Section("잠금화면 하단 + 버튼") {
                GuideRow(index: 1, text: "iOS 18 이상에서 잠금화면을 길게 누르고 사용자화를 선택합니다.")
                GuideRow(index: 2, text: "손전등 또는 카메라 원형 버튼을 탭합니다.")
                GuideRow(index: 3, text: "LockTodo 빠른 입력, LockTodo 오늘 보기, LockTodo 집중 시작 중 원하는 컨트롤을 선택합니다.")
                GuideRow(index: 4, text: "잠금화면에서는 짧게 톡 누르는 대신 컨트롤을 0.5초 정도 길게 눌러 실행합니다.")
                GuideRow(index: 5, text: "빠른 입력 컨트롤은 LockTodo를 열고 Add Task 화면의 입력창에 바로 포커스를 둡니다.")
                GuideRow(index: 6, text: "기존 컨트롤이 반응하지 않으면 삭제 후 새 LockTodo 빠른 입력 컨트롤을 다시 추가합니다.")
                GuideRow(index: 7, text: "잠금화면 하단 원형 버튼의 배경과 모양은 iOS가 그리므로 앱은 심볼과 실행 동작만 제공할 수 있습니다.")
            }

            Section("뒷면 탭") {
                GuideRow(index: 1, text: "설정 > 손쉬운 사용 > 터치로 이동합니다.")
                GuideRow(index: 2, text: "뒷면 탭을 선택합니다.")
                GuideRow(index: 3, text: "이중 탭 또는 삼중 탭을 선택합니다.")
                GuideRow(index: 4, text: "단축어 > LockTodo 새 할 일 추가를 선택합니다.")
                GuideRow(index: 5, text: "전원+볼륨 아래키 대신 이중 탭을 빠른 작성 버튼처럼 사용합니다.")
            }

            Section("Siri와 단축어") {
                GuideRow(index: 1, text: "Siri에게 “LockTodo에 할 일 추가”라고 말합니다.")
                GuideRow(index: 2, text: "Siri가 추가할 내용을 물으면 제목을 말합니다.")
                GuideRow(index: 3, text: "날짜까지 같이 말하려면 “LockTodo 스마트 입력”을 실행하고 “내일 오후 3시 병원 ! #건강”처럼 답합니다.")
                GuideRow(index: 4, text: "단축어 앱에서 LockTodo 스마트 플랜 시작 또는 잠금화면 순찰을 시간/위치 자동화에 연결할 수 있습니다.")
            }

            Section("전원/볼륨 버튼 우회") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("앱에서 직접 설정할 수 없는 것")
                        .font(.subheadline.weight(.semibold))
                    Text("볼륨 아래 버튼 단독 실행, 전원+볼륨 아래 조합 변경, 전원 버튼 3번 클릭 가로채기는 iOS 공개 API로 불가능합니다. 이 조합은 스크린샷, 긴급 구조 요청, 손쉬운 사용 단축키 같은 시스템 기능에 예약되어 있습니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("가장 가까운 우회 방법")
                        .font(.subheadline.weight(.semibold))
                    Text("Action Button이 있으면 Action Button을 사용합니다. 없으면 뒷면 탭 이중 탭에 LockTodo 새 할 일 추가를 연결하세요. 제목을 입력하거나 말하면 앱을 열지 않고 저장됩니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("잠금화면 위젯") {
                GuideRow(index: 1, text: "잠금화면을 길게 누르고 사용자화를 선택합니다.")
                GuideRow(index: 2, text: "위젯 영역에서 LockTodo를 추가합니다.")
                GuideRow(index: 3, text: "Inline, Circular, Rectangular 중 원하는 형태를 선택합니다.")
            }
        }
        .navigationTitle("빠른 실행 가이드")
    }
}

private struct GuideRow: View {
    var index: Int
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.body)
        }
        .padding(.vertical, 4)
    }
}
