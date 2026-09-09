import SwiftUI

struct TutorialView: View {
    var body: some View {
        List {
            Section {
                TutorialHero()
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .listRowBackground(Color.clear)

            Section("기본 사용") {
                TutorialStepRow(
                    number: 1,
                    title: "처음 실행하면 이 튜토리얼이 먼저 열립니다",
                    detail: "잠금화면 체크, 빠른 작성, Action Button 연결 방법을 먼저 확인한 뒤 시작합니다. 이후에는 설정에서 다시 볼 수 있습니다.",
                    systemImage: "sparkles"
                )

                TutorialStepRow(
                    number: 2,
                    title: "앱을 열면 오늘 할 일이 바로 보입니다",
                    detail: "홈 화면을 거치지 않고 Today 화면에서 남은 할 일, 완료율, 중요한 항목을 확인합니다.",
                    systemImage: "checklist"
                )

                TutorialStepRow(
                    number: 3,
                    title: "상단 + 버튼으로 빠르게 추가합니다",
                    detail: "Today 화면 오른쪽 위 + 버튼을 누르면 Add Task 화면이 열리고 입력창에 바로 포커스가 갑니다.",
                    systemImage: "plus.circle"
                )

                TutorialStepRow(
                    number: 4,
                    title: "체크, 중요 표시, 삭제를 빠르게 처리합니다",
                    detail: "원형 체크 버튼으로 완료하고, 별표로 중요한 일을 구분합니다. 행의 더보기 버튼에서 삭제와 집중 항목 설정을 할 수 있습니다.",
                    systemImage: "checkmark.circle"
                )

                TutorialStepRow(
                    number: 5,
                    title: "오늘, 내일, 나중에, 예약됨으로 분류합니다",
                    detail: "상단 분류 탭이나 상세 화면에서 날짜와 분류를 바꾸면 목록과 달력에 반영됩니다.",
                    systemImage: "tray.full"
                )

                TutorialStepRow(
                    number: 6,
                    title: "오늘 리뷰에서 미완료를 정리합니다",
                    detail: "Today 화면의 오늘 리뷰 카드는 모멘텀, 연속 완료일, 남은 중요한 일을 보여줍니다. 끝내지 못한 항목은 오늘 날짜에 남아 미달성 상태로 확인할 수 있습니다.",
                    systemImage: "sparkles"
                )
            }

            Section("잠금화면에서 쓰기") {
                TutorialStepRow(
                    number: 1,
                    title: "잠금화면 위젯을 추가합니다",
                    detail: "잠금화면을 길게 누른 뒤 사용자화 > 위젯에서 LockTodo를 고릅니다. Inline, Circular, Rectangular 중 선택할 수 있습니다.",
                    systemImage: "rectangle.on.rectangle"
                )

                TutorialStepRow(
                    number: 2,
                    title: "항목 줄을 누르면 잠금화면에서 바로 체크됩니다",
                    detail: "Rectangular 위젯과 Live Activity의 할 일 줄은 앱을 열지 않고 완료/미완료를 바꿉니다. 완료된 항목도 페이지에 남아 있으면 다시 눌러 체크를 풀 수 있습니다.",
                    systemImage: "checkmark.circle"
                )

                TutorialStepRow(
                    number: 3,
                    title: "Siri와 단축어는 앱 없이 바로 저장합니다",
                    detail: "“LockTodo에 할 일 추가”를 실행하면 시스템이 제목을 묻습니다. 이 App Intent는 잠긴 상태에서도 실행 가능하게 구성되어 있어, 입력하거나 말한 내용이 앱을 열지 않고 오늘 할 일에 저장됩니다.",
                    systemImage: "plus.circle"
                )

                TutorialStepRow(
                    number: 4,
                    title: "하단 손전등/카메라 자리에 LockTodo 버튼을 둘 수 있습니다",
                    detail: "iOS 18 이상에서는 잠금화면 사용자화에서 손전등 또는 카메라 버튼을 LockTodo 빠른 입력, 오늘 보기, 집중 시작 컨트롤로 바꿀 수 있습니다. 다만 이 컨트롤 안에는 입력창을 띄울 수 없고 앱 화면을 여는 역할만 합니다.",
                    systemImage: "checklist.checked"
                )

                TutorialStepRow(
                    number: 5,
                    title: "상시 위젯과 실시간 현황은 역할이 다릅니다",
                    detail: "잠금화면 편집에서 LockTodo 직사각형 위젯을 추가하면 제거하기 전까지 계속 표시됩니다. Today 화면의 실시간 현황은 위치 도착이나 집중을 위한 Live Activity이며 iOS 정책상 최대 12시간 안에 종료될 수 있습니다.",
                    systemImage: "pin"
                )

                TutorialStepRow(
                    number: 6,
                    title: "Dynamic Island에서 남은 개수를 확인합니다",
                    detail: "지원 기기에서는 compact 상태에 남은 개수가 보이고, 길게 누르면 중요한 항목과 진행률이 펼쳐집니다. 펼친 항목도 바로 체크할 수 있습니다.",
                    systemImage: "dynamicisland"
                )

                TutorialStepRow(
                    number: 7,
                    title: "목록은 페이지 버튼으로 넘깁니다",
                    detail: "iOS 잠금화면 위젯은 손가락 스크롤을 지원하지 않습니다. 대신 LockTodo는 Live Activity의 좌우 버튼과 Rectangular 위젯의 › 버튼으로 다음 할 일을 넘겨 봅니다.",
                    systemImage: "chevron.right.circle"
                )

                TutorialStepRow(
                    number: 8,
                    title: "목록이 안 보이면 권한과 표시 방식을 확인합니다",
                    detail: "상시 목록은 잠금화면 편집에서 직접 추가해야 합니다. 큰 실시간 현황 카드는 앱에서 시작하며, 설정 > LockTodo에서 Live Activities가 켜져 있어야 합니다.",
                    systemImage: "exclamationmark.circle"
                )
            }

            Section("빠른 실행") {
                TutorialStepRow(
                    number: 1,
                    title: "Action Button",
                    detail: "iPhone 15 Pro 이상은 설정 > 동작 버튼 > 단축어 > LockTodo 새 할 일 추가를 선택합니다. 실행하면 제목을 묻고, 입력한 내용은 앱을 열지 않고 바로 저장됩니다.",
                    systemImage: "button.programmable"
                )

                TutorialStepRow(
                    number: 2,
                    title: "뒷면 탭",
                    detail: "설정 > 손쉬운 사용 > 터치 > 뒷면 탭 > 단축어 > LockTodo 새 할 일 추가를 선택합니다.",
                    systemImage: "hand.tap"
                )

                TutorialStepRow(
                    number: 3,
                    title: "Siri",
                    detail: "Siri에게 “LockTodo에 할 일 추가”라고 말하면 추가할 내용을 물어봅니다. 답한 내용은 앱을 열지 않고 오늘 할 일에 저장됩니다.",
                    systemImage: "waveform"
                )

                TutorialStepRow(
                    number: 4,
                    title: "잠금화면 하단 컨트롤",
                    detail: "iOS 18 이상에서 잠금화면 하단 버튼을 LockTodo 빠른 입력으로 바꾸면, 길게 눌렀을 때 앱이 열리고 Add Task 입력창에 바로 포커스가 갑니다. 잠금화면 위에 앱 키보드를 직접 띄우는 것은 iOS에서 허용되지 않습니다.",
                    systemImage: "checklist.checked"
                )

                TutorialStepRow(
                    number: 5,
                    title: "볼륨/전원 버튼",
                    detail: "볼륨 아래 버튼과 전원+볼륨 아래 조합은 iOS 시스템 기능이라 앱이 직접 감지하거나 변경할 수 없습니다. 대신 뒷면 탭 이중 탭을 LockTodo 새 할 일 추가에 연결하면 가장 비슷하게 쓸 수 있습니다.",
                    systemImage: "speaker.minus"
                )
            }

            Section("달력과 알림") {
                TutorialStepRow(
                    number: 1,
                    title: "달력에서 날짜별 할 일을 봅니다",
                    detail: "달력 탭에서 날짜를 누르면 해당 날짜의 할 일과 완료율을 확인하고 바로 추가할 수 있습니다.",
                    systemImage: "calendar"
                )

                TutorialStepRow(
                    number: 2,
                    title: "알림 권한을 켭니다",
                    detail: "설정 > 알림 권한 요청을 누르면 시간 알림과 저녁 미완료 알림을 사용할 수 있습니다.",
                    systemImage: "bell"
                )

                TutorialStepRow(
                    number: 3,
                    title: "상세 화면에서 반복, 메모, 태그를 관리합니다",
                    detail: "할 일을 눌러 상세 화면에 들어가면 마감 시간, 알림 시간, 반복, 메모, 태그를 조정할 수 있습니다.",
                    systemImage: "slider.horizontal.3"
                )
            }

            Section("중요한 제한") {
                Label("잠금화면 위젯/Live Activity 안에는 키보드를 띄울 수 없지만 Siri와 단축어는 앱 없이 바로 저장할 수 있습니다.", systemImage: "lock")
                Label("Action Button과 뒷면 탭 연결은 iOS 설정 앱에서만 최종 연결할 수 있습니다.", systemImage: "button.programmable")
                Label("전원/볼륨 버튼 조합은 앱이 우회해서 사용할 수 없는 시스템 예약 버튼입니다.", systemImage: "exclamationmark.triangle")
                Label("데이터는 서버 없이 iPhone 안의 SwiftData 저장소에만 저장됩니다.", systemImage: "iphone")
            }
            .font(.footnote)
        }
        .navigationTitle("사용 튜토리얼")
    }
}

private struct TutorialHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "checklist.checked")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.46, green: 0.67, blue: 1.0),
                            Color(red: 0.54, green: 0.48, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("LockTodo는 오늘 할 일을 잠금화면에서 확인하고, Siri와 단축어로 앱 없이 빠르게 저장할 수 있게 만든 체크리스트입니다.")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            Text("핵심 흐름은 입력, 확인, 완료입니다.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct TutorialStepRow: View {
    var number: Int
    var title: String
    var detail: String
    var systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("\(number). \(title)")
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        TutorialView()
    }
}
