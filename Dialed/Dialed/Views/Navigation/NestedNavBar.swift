//
//  NestedNavBar.swift
//  Dialed
//
//  Floating bottom navigation with nested menus. Each section is a round
//  avatar; the selected one springs open into a dark pill showing its
//  name and a menu button. The menu nests: every tab has a Log submenu,
//  Home adds Ask Dialed and a "Go to" submenu, Challenge adds weigh-ins.
//
//  The pill is always dark glass so it reads on the light Neka screens and
//  the legacy dark ones alike.
//

import SwiftUI

struct NestedNavBar: View {
    @ObservedObject var router: AppRouter
    @ObservedObject private var photos = ProfilePhotoStore.shared
    @Namespace private var pillSpace

    /// Height of the docked bar (above the home indicator).
    static let height: CGFloat = 70

    private let tabs: [AppTab] = [.home, .challenge, .plan, .trends, .settings]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tabs, id: \.self) { tab in
                if tab == router.tab {
                    pill(tab)
                        .transition(.opacity)
                } else {
                    Button {
                        #if os(iOS)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        #endif
                        router.select(tab)
                    } label: {
                        avatar(tab, size: 44)
                            .matchedGeometryEffect(id: "avatar-\(tab.rawValue)", in: pillSpace)
                    }
                    .buttonStyle(.dialedScale)
                    .accessibilityLabel(tab.title)
                }
            }
        }
        .padding(6)
        // One contained dock, so the bar reads as its own surface instead of
        // loose circles floating over content.
        .background(
            Capsule()
                .fill(.regularMaterial)
                .overlay(Capsule().stroke(Neka.hairline, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(height: Self.height)
        // Docked: an opaque strip in the page color runs from the bar's top
        // edge down through the home indicator. No fade above it — that hid
        // the last bit of every page.
        .background {
            pageColor
                .overlay(alignment: .top) {
                    Rectangle().fill(Neka.hairline).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: router.tab)
    }

    /// Plan and Trends are still dark-designed; match whichever page is up.
    private var pageColor: Color {
        switch router.tab {
        case .plan: return Neka.paper
        default:             return Neka.paper
        }
    }

    // MARK: - Selected pill

    private func pill(_ tab: AppTab) -> some View {
        HStack(spacing: 10) {
            avatar(tab, size: 32)
                .matchedGeometryEffect(id: "avatar-\(tab.rawValue)", in: pillSpace)
            Text(tab.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            Menu {
                menu(for: tab)
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .accessibilityLabel("\(tab.title) menu")
        }
        .padding(.leading, 7)
        .padding(.trailing, 6)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(
            Capsule()
                .fill(Color(hex: "17181B").opacity(0.94))
                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                .matchedGeometryEffect(id: "pill", in: pillSpace)
        )
    }

    // MARK: - Nested menus

    @ViewBuilder
    private func menu(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            logMenu
            Button { router.openHome(.ask) } label: {
                Label("Ask Dialed", systemImage: "sparkles")
            }
            Button { router.openHome(.avatar) } label: {
                Label("Your avatar & future you", systemImage: "person.crop.circle.badge.checkmark")
            }
            Menu {
                ForEach(HomeDestination.allCases, id: \.self) { destination in
                    Button { router.openHome(destination) } label: {
                        Label(destination.title, systemImage: destination.icon)
                    }
                }
            } label: {
                Label("Go to", systemImage: "square.grid.2x2")
            }
            Divider()
            Button { router.openHome(.profile) } label: {
                Label("Profile & photo", systemImage: "person.crop.circle")
            }

        case .challenge:
            let challenge = WeightChallenge.load()
            logMenu
            if let challenge {
                Menu {
                    Button { router.openChallenge(.weighIn) } label: {
                        Label("My weigh-in", systemImage: "scalemass.fill")
                    }
                    Button { router.openChallenge(.friend) } label: {
                        Label("\(challenge.friendDisplayName)'s weigh-in", systemImage: "person.fill")
                    }
                } label: {
                    Label("Weigh-ins", systemImage: "chart.line.downtrend.xyaxis")
                }
                Divider()
                Button { router.openChallenge(.edit) } label: {
                    Label("Edit challenge", systemImage: "slider.horizontal.3")
                }
            } else {
                Button { router.openChallenge(.setup) } label: {
                    Label("Start a challenge", systemImage: "flag.2.crossed.fill")
                }
            }

        case .trends:
            logMenu
            ForEach(HealthSection.allCases) { section in
                Button { router.openHealth(section) } label: {
                    Label(section.title, systemImage: section.icon)
                }
            }

        case .plan, .settings:
            logMenu
            Button { router.openHome(.workout) } label: {
                Label("Workout plan", systemImage: "dumbbell.fill")
            }
            Menu {
                Button { router.openHome(.ask) } label: {
                    Label("Ask Dialed", systemImage: "sparkles")
                }
                Button { router.openHome(.devices) } label: {
                    Label("Devices & data check", systemImage: "dot.radiowaves.left.and.right")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    /// "Log ▸ Water / Weigh in / Meal / Voice note" — on every tab.
    private var logMenu: some View {
        Menu {
            ForEach(QuickLog.allCases) { item in
                Button { router.quickLog = item } label: {
                    Label(item.title, systemImage: item.icon)
                }
            }
        } label: {
            Label("Log", systemImage: "plus.circle.fill")
        }
    }

    // MARK: - Avatars

    @ViewBuilder
    private func avatar(_ tab: AppTab, size: CGFloat) -> some View {
        if tab == .home, let photo = photos.thumbnail {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        } else {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: tab.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: tab.icon)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        }
    }
}

extension AppTab {
    var title: String {
        switch self {
        case .home:      return "Today"
        case .challenge: return "Challenge"
        case .plan:      return "Plan"
        case .trends:    return "Health"
        case .settings:  return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home:      return "house.fill"
        case .challenge: return "flag.2.crossed.fill"
        case .plan:      return "calendar.day.timeline.left"
        case .trends:    return "heart.text.square.fill"
        case .settings:  return "gearshape.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .home:      return [Color(hex: "9BE2AE"), Neka.green]
        case .challenge: return [Color(hex: "FFC58F"), Neka.orange]
        case .plan:      return [Color(hex: "9FD3F7"), Neka.sky]
        case .trends:    return [Color(hex: "C9B3F5"), Neka.lavender]
        case .settings:  return [Color(hex: "B9BCC4"), Color(hex: "7C8089")]
        }
    }
}
