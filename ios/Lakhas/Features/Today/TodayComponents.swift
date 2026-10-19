import LakhasKit
import SwiftData
import SwiftUI

/// Mark + "Today"/date + Progress and Settings buttons (Progress moved here per ADR-017).
struct TodayHeader: View {
    let date: Date
    let isToday: Bool
    private let format = AppFormat.current

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Text("common.appName")
                .font(.title3.bold())
                .foregroundStyle(Theme.Palette.onPrimary)
                .frame(width: 44, height: 44)
                .background(Theme.Palette.primary, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(isToday ? LocalizedStringKey("today.title") : LocalizedStringKey("today.pastDay"))
                    .font(.title2.bold())
                    .foregroundStyle(Theme.Palette.ink)
                Text(verbatim: format.longDate(date))
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.muted)
            }
            Spacer()
            NavigationLink {
                ProgressScreen()
            } label: {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(Theme.Palette.surface, in: Circle())
            }
            .accessibilityLabel(Text("progress.title"))
            .accessibilityIdentifier("ax.today.progress")
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(Theme.Palette.surface, in: Circle())
            }
            .accessibilityLabel(Text("settings.title"))
            .accessibilityIdentifier("ax.today.settings")
        }
        .tint(Theme.Palette.ink)
    }
}

/// Last 7 days, oldest → newest in reading direction (flips in Arabic). Days with logs get a dot.
struct DateStrip: View {
    @Binding var selectedDate: Date
    @Query private var recentMeals: [Meal]
    private let format = AppFormat.current
    private let days: [Date]

    init(selectedDate: Binding<Date>) {
        _selectedDate = selectedDate
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let start = days.first ?? today
        _recentMeals = Query(filter: #Predicate<Meal> { $0.loggedAt >= start })
    }

    var body: some View {
        let logged = Set(recentMeals.map(\.dayKey))
        HStack(spacing: 2) {
            ForEach(days, id: \.self) { day in
                let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
                Button {
                    selectedDate = day
                } label: {
                    VStack(spacing: 2) {
                        Text(verbatim: format.weekdayInitial(day))
                            .font(.caption2)
                            .foregroundStyle(isSelected ? Theme.Palette.onPrimary.opacity(0.85) : Theme.Palette.muted)
                        Text(verbatim: format.day(day))
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .foregroundStyle(isSelected ? Theme.Palette.onPrimary : Theme.Palette.ink)
                        Circle()
                            .fill(dotColor(logged: logged.contains(DayKey.make(day)), selected: isSelected))
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(isSelected ? Theme.Palette.primary : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: format.longDate(day)))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

extension DateStrip {
    fileprivate func dotColor(logged: Bool, selected: Bool) -> Color {
        guard logged else { return .clear }
        return selected ? Theme.Palette.onPrimary : Theme.Palette.primary
    }
}

/// 148pt ring, fills clockwise in both languages (docs/design.md §4).
struct CalorieRing: View {
    let eaten: Double
    let target: Int
    let format: AppFormat

    private var progress: Double { target > 0 ? eaten / Double(target) : 0 }
    private var remaining: Int { target - Int(eaten.rounded()) }
    private var isOver: Bool { remaining < 0 }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.Palette.track, lineWidth: 14)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(isOver ? Theme.Palette.accent : Theme.Palette.primary,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: progress)
            VStack(spacing: 2) {
                Text(verbatim: format.number(abs(remaining)))
                    .font(.largeTitle.bold().monospacedDigit())
                    .foregroundStyle(isOver ? Theme.Palette.accent : Theme.Palette.ink)
                    .contentTransition(.numericText())
                Text(isOver ? LocalizedStringKey("today.ring.over") : LocalizedStringKey("today.ring.left"))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.muted)
                Text(verbatim: "\(format.number(Int(eaten.rounded()))) / \(format.number(target))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.muted)
            }
        }
        .environment(\.layoutDirection, .leftToRight)   // the ring never mirrors
        .frame(width: 148, height: 148)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("today.ring.a11yLabel"))
        .accessibilityValue(Text(verbatim: accessibilityValue))
        .accessibilityIdentifier("ax.today.ring")
    }

    private var accessibilityValue: String {
        let eatenText = format.number(Int(eaten.rounded()))
        let targetText = format.number(target)
        if isOver {
            return String(localized: "today.ring.a11yOver \(eatenText) \(targetText) \(format.number(-remaining))")
        }
        return String(localized: "today.ring.a11yLeft \(eatenText) \(targetText) \(format.number(remaining))")
    }
}

struct MealCard: View {
    let meal: Meal
    let format: AppFormat

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            MealThumbnail(fileName: meal.photoFileName)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: meal.displayName(language: format.language))
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
                Text(verbatim: macroLine)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text(verbatim: format.number(Int(meal.totals.kcal.rounded())))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.Palette.ink)
                Text("unit.kcal")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.muted)
            }
        }
        .padding(Theme.Space.sm)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .shadow(color: Theme.Palette.ink.opacity(0.06), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ax.today.meal")
    }

    private var macroLine: String {
        let totals = meal.totals
        let grams = String(localized: "unit.g")
        return [
            "\(String(localized: "macro.protein.short")) \(format.number(Int(totals.protein.rounded())))\(grams)",
            "\(String(localized: "macro.carbs.short")) \(format.number(Int(totals.carbs.rounded())))\(grams)",
            "\(String(localized: "macro.fat.short")) \(format.number(Int(totals.fat.rounded())))\(grams)",
        ].joined(separator: " · ")
    }
}

/// The photo the user took (device only), otherwise a styled placeholder plate (ADR-020).
struct MealThumbnail: View {
    let fileName: String?
    /// Placeholder symbol (dish-category style) when there's no photo.
    var symbol = "fork.knife"

    var body: some View {
        Group {
            if let fileName, let image = UIImage(contentsOfFile: MealPhotoStore().url(for: fileName).path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Palette.surfaceSunken)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.Palette.line, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Sesame-dot confetti in the macro colors; a calm checkmark under Reduce Motion.
struct CelebrationView: View {
    let reduceMotion: Bool
    @State private var start = Date.now

    var body: some View {
        if reduceMotion {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.Palette.primary)
                .transition(.opacity)
                .accessibilityLabel(Text("today.celebrate"))
        } else {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let elapsed = timeline.date.timeIntervalSince(start)
                    let colors = [Theme.Palette.protein, Theme.Palette.carbs, Theme.Palette.fat, Theme.Palette.primary]
                    for index in 0..<60 {
                        let seed = Double(index)
                        let x = size.width * (0.1 + 0.8 * ((seed * 37).truncatingRemainder(dividingBy: 100) / 100))
                        let y = -20 + elapsed * (220 + (seed * 13).truncatingRemainder(dividingBy: 160))
                        let rect = CGRect(x: x + sin(elapsed * 3 + seed) * 18, y: y, width: 5, height: 9)
                        context.fill(Path(ellipseIn: rect), with: .color(colors[index % colors.count]))
                    }
                }
            }
            .ignoresSafeArea()
            .accessibilityLabel(Text("today.celebrate"))
        }
    }
}

struct ProgressScreen: View {
    var body: some View {
        PlaceholderView(titleKey: "progress.title")
    }
}

/// Settings (Phase 11 adds goals, language, units, reminders, backup).
struct SettingsView: View {
    @Environment(AccountModel.self) private var account
    @State private var settings = AISettings.load()
    @State private var hasKey = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AccountView()
                } label: {
                    LabeledContent {
                        if let session = account.session {
                            Text(verbatim: session.email)
                                .lineLimit(1)
                                .environment(\.layoutDirection, .leftToRight)
                        } else {
                            Text("settings.account.signedOut")
                        }
                    } label: {
                        Label("account.title", systemImage: "person.crop.circle")
                    }
                }
                .accessibilityIdentifier("ax.settings.account")
            } footer: {
                Text("settings.account.footer")
            }
            Section {
                NavigationLink {
                    AISettingsView()
                } label: {
                    LabeledContent {
                        Text(hasKey ? LocalizedStringKey("settings.ai.ready") : LocalizedStringKey("settings.ai.noKey"))
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ai.title")
                                Text(verbatim: settings.provider.displayName)
                                    .font(.caption)
                                    .foregroundStyle(Theme.Palette.muted)
                            }
                        } icon: {
                            Image(systemName: "sparkles")
                        }
                    }
                }
                .accessibilityIdentifier("ax.settings.ai")
            }
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("barcode.off.attribution").font(.footnote)
                    if let url = OpenFoodFactsClient.attributionURL {
                        Link(destination: url) { Text("barcode.off.link").font(.footnote) }
                    }
                    if let url = OpenFoodFactsClient.licenseURL {
                        Link(destination: url) { Text("settings.about.odbl").font(.footnote) }
                    }
                }
                Link(destination: ServerConfig.privacyURL(language: AppFormat.current.language)) {
                    Text("account.privacy").font(.footnote)
                }
            } header: {
                Text("settings.about")
            }
            #if !LAKHAS_STORE
            // Sideload-only (ADR-027 §10): hidden in an App Store build.
            Section {
                NavigationLink {
                    CapabilityProbeView()
                } label: {
                    Label("probe.title", systemImage: "stethoscope")
                }
            }
            #endif
        }
        .navigationTitle("settings.title")
        .onAppear {
            settings = AISettings.load()
            hasKey = AIKeyStore().hasKey(for: settings.provider)
        }
    }
}
