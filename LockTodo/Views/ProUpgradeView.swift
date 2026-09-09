import SwiftUI
import StoreKit

/// LockTodo Pro paywall — subscription (monthly / yearly) alongside a one-time
/// lifetime unlock, so both recurring revenue and subscription-averse users are
/// captured. The whole app stays usable free; Pro unlocks monthly insights and
/// advanced lock-screen widget styles.
struct ProUpgradeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var proAccess = ProAccessService.shared

    @State private var selectedID = ProAccessService.yearlyProductID

    /// App Review requires a working EULA link on subscription paywalls; this is
    /// Apple's standard EULA. Replace the privacy URL with your own hosted page.
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private let privacyURL = URL(string: "https://www.apple.com/legal/privacy/")!

    private let benefits: [(String, String)] = [
        ("chart.bar.xaxis", "월간 인사이트와 완료 추이 분석"),
        ("rectangle.on.rectangle.angled", "고급 잠금화면 위젯 스타일"),
        ("wand.and.stars", "앞으로 추가되는 Pro 기능 모두 포함")
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    hero
                    benefitList
                    if proAccess.isPro {
                        activeState
                    } else {
                        productOptions
                        subscribeButton
                        footer
                    }
                }
                .padding(.horizontal, LockTodoDesign.pageInset)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(LockTodoDesign.pageBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("닫기")
                }
                if !proAccess.isPro {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("복원") { Task { await proAccess.restorePurchases() } }
                            .font(.subheadline)
                    }
                }
            }
            .task {
                await proAccess.loadProducts()
                await proAccess.refreshEntitlements()
            }
            .onChange(of: proAccess.isPro) { _, isPro in
                if isPro { dismiss() }
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(
                    LinearGradient(colors: [Color(hex: "#FF9500"), Color(hex: "#FF5E3A")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .shadow(color: Color(hex: "#FF5E3A").opacity(0.3), radius: 14, y: 6)

            Text("LockTodo Pro")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.6)

            Text(proAccess.isPro
                 ? "Pro가 활성화되어 있어요."
                 : "월간 인사이트와 고급 잠금화면 스타일을 잠금 해제하세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    // MARK: Benefits

    private var benefitList: some View {
        VStack(spacing: 12) {
            ForEach(benefits, id: \.1) { icon, text in
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 30, height: 30)
                        .background(Color.accentColor.opacity(0.12), in: Circle())
                    Text(text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .lockTodoCard()
    }

    private var activeState: some View {
        Label("이 Apple 계정에서 Pro 이용 가능", systemImage: "checkmark.seal.fill")
            .font(.headline)
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .lockTodoCard()
    }

    // MARK: Products

    @ViewBuilder
    private var productOptions: some View {
        if proAccess.products.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
        } else {
            VStack(spacing: 10) {
                ForEach(proAccess.products, id: \.id) { product in
                    optionCard(product)
                }
            }
        }
    }

    private func optionCard(_ product: Product) -> some View {
        let isSelected = selectedID == product.id
        let isLifetime = product.id == ProAccessService.lifetimeProductID
        let isRecommended = product.id == ProAccessService.yearlyProductID
        let shape = RoundedRectangle(cornerRadius: LockTodoDesign.tileRadius, style: .continuous)

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(LockTodoMotion.snappy) { selectedID = product.id }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(optionTitle(product, isLifetime: isLifetime))
                        .font(.subheadline.weight(.semibold))
                    Text(optionSubtitle(product, isLifetime: isLifetime))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if isRecommended {
                    Text("추천")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor, in: Capsule())
                }
            }
            .padding(14)
            .background(LockTodoDesign.cardBackground, in: shape)
            .overlay {
                shape.strokeBorder(isSelected ? Color.accentColor : LockTodoDesign.separator,
                                   lineWidth: isSelected ? 2 : LockTodoDesign.hairline)
            }
        }
        .buttonStyle(.lockTodoSurface)
    }

    private func optionTitle(_ product: Product, isLifetime: Bool) -> String {
        if isLifetime { return "평생 이용권" }
        return product.id == ProAccessService.yearlyProductID ? "연간 구독" : "월간 구독"
    }

    private func optionSubtitle(_ product: Product, isLifetime: Bool) -> String {
        if let suffix = product.lockTodoPeriodSuffix {
            return "\(product.displayPrice) / \(suffix) · 자동 갱신"
        }
        return "\(product.displayPrice) · 한 번 결제로 영구 이용"
    }

    // MARK: Actions

    private var subscribeButton: some View {
        let isLifetime = selectedID == ProAccessService.lifetimeProductID
        let isBusy = proAccess.purchasingProductID != nil
        return Button {
            guard let product = proAccess.products.first(where: { $0.id == selectedID }) else { return }
            Task { await proAccess.purchase(product) }
        } label: {
            Group {
                if isBusy {
                    ProgressView().tint(.white)
                } else {
                    Text(isLifetime ? "평생 이용권 구매" : "구독 시작하기")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .disabled(isBusy || proAccess.products.isEmpty)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let message = proAccess.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            // Auto-renew disclosure is required by App Review for subscriptions.
            Text("구독은 기간 종료 24시간 전에 취소하지 않으면 자동 갱신되며 App Store 계정으로 청구됩니다. 평생 이용권은 일회성 결제입니다. 설정에서 언제든 관리·해지할 수 있습니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 16) {
                Link("이용약관", destination: termsURL)
                Text("·").foregroundStyle(.tertiary)
                Link("개인정보 처리방침", destination: privacyURL)
            }
            .font(.caption2.weight(.medium))
        }
        .padding(.top, 4)
    }
}
