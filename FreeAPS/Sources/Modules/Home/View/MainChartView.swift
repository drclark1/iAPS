import Algorithms
import SwiftDate
import SwiftUI

private enum PredictionType: Hashable {
    case iob
    case cob
    case zt
    case uam
}

struct MainChartView: View {
    private enum Config {
        static let screenHours = 6
        static let basalHeight: CGFloat = 60
        static let topYPadding: CGFloat = 20
        static let bottomYPadding: CGFloat = 50

        static let yLinesCount = 5
    }

    @Binding var glucose: [BloodGlucose]
    @Binding var suggestion: Suggestion?
    @Binding var hours: Int
    let units: GlucoseUnits

    @State var didAppearTrigger = false
    @State private var glucoseDots: [CGRect] = []
    @State private var predictionDots: [PredictionType: [CGRect]] = [:]

    private var dateDormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Path { path in
                    let range = glucoseYRange(fullSize: geo.size)
                    let step = (range.maxY - range.minY) / CGFloat(Config.yLinesCount)
                    for line in 0 ... Config.yLinesCount {
                        path.move(to: CGPoint(x: 0, y: range.minY + CGFloat(line) * step))
                        path.addLine(to: CGPoint(x: geo.size.width, y: range.minY + CGFloat(line) * step))
                    }
                }.stroke(Color.secondary, lineWidth: 0.2)

                ScrollView(.horizontal, showsIndicators: false) {
                    ScrollViewReader { scroll in
                        ZStack(alignment: .top) {
                            basalChart(fullSize: geo.size)
                            mainChart(fullSize: geo.size)
                                .onChange(of: glucose) { _ in
                                    scroll.scrollTo("End")
                                }
                                .onAppear {
                                    scroll.scrollTo("End")
                                    // add trigger to the end of main queue
                                    DispatchQueue.main.async {
                                        didAppearTrigger = true
                                    }
                                }
                        }
                    }
                }
                ForEach(0 ..< Config.yLinesCount) { line -> AnyView in
                    let range = glucoseYRange(fullSize: geo.size)
                    let yStep = (range.maxY - range.minY) / CGFloat(Config.yLinesCount)
                    let valueStep = Double(range.maxValue - range.minValue) / Double(Config.yLinesCount)
                    let value = round(Double(range.maxValue) - Double(line) * valueStep) *
                        (units == .mmolL ? Double(GlucoseUnits.exchangeRate) : 1)

                    return Text(glucoseFormatter.string(from: value as NSNumber)!)
                        .position(CGPoint(x: geo.size.width - 12, y: range.minY + CGFloat(line) * yStep))
                        .font(.caption2)
                        .asAny()
                }
            }
        }
    }

    private func basalChart(fullSize: CGSize) -> some View {
        Group {
            EmptyView()
        }
        .frame(width: fullGlucoseWidth(viewWidth: fullSize.width) + additionalWidth(viewWidth: fullSize.width))
        .frame(maxHeight: Config.basalHeight).background(Color.secondary.opacity(0.1))
    }

    private func mainChart(fullSize: CGSize) -> some View {
        Group {
            VStack {
                ZStack {
                    Path { path in
                        for hour in 0 ..< hours + hours {
                            let x = firstHourPosition(viewWidth: fullSize.width) +
                                oneSecondStep(viewWidth: fullSize.width) *
                                CGFloat(hour) * CGFloat(1.hours.timeInterval)
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: fullSize.height - 20))
                        }
                    }
                    .stroke(Color.secondary, lineWidth: 0.2)
                    glucosePath(fullSize: fullSize)
                    predictions(fullSize: fullSize).id("End")
                }
                ZStack {
                    ForEach(0 ..< hours + hours) { hour in
                        Text(dateDormatter.string(from: firstHourDate().addingTimeInterval(hour.hours.timeInterval)))
                            .font(.caption)
                            .position(
                                x: firstHourPosition(viewWidth: fullSize.width) +
                                    oneSecondStep(viewWidth: fullSize.width) *
                                    CGFloat(hour) * CGFloat(1.hours.timeInterval),
                                y: 10.0
                            )
                            .foregroundColor(.secondary)
                    }
                }.frame(maxHeight: 20)
            }
        }
        .frame(width: fullGlucoseWidth(viewWidth: fullSize.width) + additionalWidth(viewWidth: fullSize.width))
    }

    private func glucosePath(fullSize: CGSize) -> some View {
        Path { path in
            for rect in glucoseDots {
                path.addEllipse(in: rect)
            }
        }
        .fill(Color.green)
        .onChange(of: glucose) { _ in
            calculateGlucoseDots(fullSize: fullSize)
        }
        .onChange(of: didAppearTrigger) { _ in
            calculateGlucoseDots(fullSize: fullSize)
        }
    }

    private func calculateGlucoseDots(fullSize: CGSize) {
        glucoseDots = glucose.concurrentMap { value -> CGRect in
            let position = glucoseToCoordinate(value, fullSize: fullSize)
            return CGRect(x: position.x - 2, y: position.y - 2, width: 4, height: 4)
        }
    }

    private func calculatePredictionDots(fullSize: CGSize, type: PredictionType) {
        let values: [Int] = { () -> [Int] in
            switch type {
            case .iob:
                return suggestion?.predictions?.iob ?? []
            case .cob:
                return suggestion?.predictions?.cob ?? []
            case .zt:
                return suggestion?.predictions?.zt ?? []
            case .uam:
                return suggestion?.predictions?.uam ?? []
            }
        }()

        var index = 0
        predictionDots[type] = values.concurrentMap { value -> CGRect in
            let position = predictionToCoordinate(value, fullSize: fullSize, index: index)
            index += 1
            return CGRect(x: position.x - 2, y: position.y - 2, width: 4, height: 4)
        }
    }

    private func predictions(fullSize: CGSize) -> some View {
        Group {
            Path { path in
                for rect in predictionDots[.iob] ?? [] {
                    path.addEllipse(in: rect)
                }
            }.stroke(Color.blue)

            Path { path in
                for rect in predictionDots[.cob] ?? [] {
                    path.addEllipse(in: rect)
                }
            }.stroke(Color.yellow)

            Path { path in
                for rect in predictionDots[.zt] ?? [] {
                    path.addEllipse(in: rect)
                }
            }.stroke(Color.purple)

            Path { path in
                for rect in predictionDots[.uam] ?? [] {
                    path.addEllipse(in: rect)
                }
            }.stroke(Color.orange)
        }
        .onChange(of: suggestion) { _ in
            calculatePredictionDots(fullSize: fullSize, type: .iob)
            calculatePredictionDots(fullSize: fullSize, type: .cob)
            calculatePredictionDots(fullSize: fullSize, type: .zt)
            calculatePredictionDots(fullSize: fullSize, type: .uam)
        }
        .onChange(of: didAppearTrigger) { _ in
            calculatePredictionDots(fullSize: fullSize, type: .iob)
            calculatePredictionDots(fullSize: fullSize, type: .cob)
            calculatePredictionDots(fullSize: fullSize, type: .zt)
            calculatePredictionDots(fullSize: fullSize, type: .uam)
        }
    }

    private func fullGlucoseWidth(viewWidth: CGFloat) -> CGFloat {
        viewWidth * CGFloat(hours) / CGFloat(Config.screenHours)
    }

    private func additionalWidth(viewWidth: CGFloat) -> CGFloat {
        guard let predictions = suggestion?.predictions,
              let deliveredAt = suggestion?.deliverAt,
              let last = glucose.last
        else {
            return 0
        }

        let iob = predictions.iob?.count ?? 0
        let zt = predictions.zt?.count ?? 0
        let cob = predictions.cob?.count ?? 0
        let uam = predictions.uam?.count ?? 0
        let max = [iob, zt, cob, uam].max() ?? 0

        let lastDeltaTime = last.dateString.timeIntervalSince(deliveredAt)
        let additionalTime = CGFloat(TimeInterval(max) * 5.minutes.timeInterval - lastDeltaTime)
        let oneSecondWidth = oneSecondStep(viewWidth: viewWidth)

        return additionalTime * oneSecondWidth
    }

    private func oneSecondStep(viewWidth: CGFloat) -> CGFloat {
        viewWidth / (CGFloat(Config.screenHours) * CGFloat(1.hours.timeInterval))
    }

    private func maxPredValue() -> Int {
        [
            suggestion?.predictions?.cob ?? [],
            suggestion?.predictions?.iob ?? [],
            suggestion?.predictions?.zt ?? [],
            suggestion?.predictions?.uam ?? []
        ]
        .flatMap { $0 }
        .max() ?? 450
    }

    private func minPredValue() -> Int {
        [
            suggestion?.predictions?.cob ?? [],
            suggestion?.predictions?.iob ?? [],
            suggestion?.predictions?.zt ?? [],
            suggestion?.predictions?.uam ?? []
        ]
        .flatMap { $0 }
        .min() ?? 0
    }

    private func glucoseToCoordinate(_ glucoseEntry: BloodGlucose, fullSize: CGSize) -> CGPoint {
        guard let first = glucose.first else {
            return .zero
        }
        let topYPaddint = Config.topYPadding + Config.basalHeight
        let bottomYPadding = Config.bottomYPadding
        let maxValue = max(glucose.compactMap(\.glucose).max() ?? 450, maxPredValue())
        let minValue = min(glucose.compactMap(\.glucose).min() ?? 0, minPredValue())
        let stepYFraction = (fullSize.height - topYPaddint - bottomYPadding) / CGFloat(maxValue - minValue)
        let yOffset = CGFloat(minValue) * stepYFraction
        let xOffset = -first.dateString.timeIntervalSince1970
        let stepXFraction = fullGlucoseWidth(viewWidth: fullSize.width) / CGFloat(hours.hours.timeInterval)
        let x = CGFloat(glucoseEntry.dateString.timeIntervalSince1970 + xOffset) * stepXFraction
        let y = fullSize.height - CGFloat(glucoseEntry.glucose ?? 0) * stepYFraction + yOffset - bottomYPadding

        return CGPoint(x: x, y: y)
    }

    private func predictionToCoordinate(_ pred: Int, fullSize: CGSize, index: Int) -> CGPoint {
        guard let first = glucose.first, let deliveredAt = suggestion?.deliverAt else {
            return .zero
        }
        let topYPaddint = Config.topYPadding + Config.basalHeight
        let bottomYPadding = Config.bottomYPadding
        let maxValue = max(glucose.compactMap(\.glucose).max() ?? 450, maxPredValue())
        let minValue = min(glucose.compactMap(\.glucose).min() ?? 0, minPredValue())
        let stepYFraction = (fullSize.height - topYPaddint - bottomYPadding) / CGFloat(maxValue - minValue)
        let yOffset = CGFloat(minValue) * stepYFraction
        let xOffset = -first.dateString.timeIntervalSince1970
        let stepXFraction = fullGlucoseWidth(viewWidth: fullSize.width) / CGFloat(hours.hours.timeInterval)
        let predTime = deliveredAt.timeIntervalSince1970 + TimeInterval(index) * 5.minutes.timeInterval
        let x = CGFloat(predTime + xOffset) * stepXFraction
        let y = fullSize.height - CGFloat(pred) * stepYFraction + yOffset - bottomYPadding

        return CGPoint(x: x, y: y)
    }

    private func glucoseYRange(fullSize: CGSize) -> (minValue: Int, minY: CGFloat, maxValue: Int, maxY: CGFloat) {
        let topYPaddint = Config.topYPadding + Config.basalHeight
        let bottomYPadding = Config.bottomYPadding
        let maxValue = max(glucose.compactMap(\.glucose).max() ?? 450, maxPredValue())
        let minValue = min(glucose.compactMap(\.glucose).min() ?? 0, minPredValue())
        let stepYFraction = (fullSize.height - topYPaddint - bottomYPadding) / CGFloat(maxValue - minValue)
        let yOffset = CGFloat(minValue) * stepYFraction
        let maxY = fullSize.height - CGFloat(minValue) * stepYFraction + yOffset - bottomYPadding
        let minY = fullSize.height - CGFloat(maxValue) * stepYFraction + yOffset - bottomYPadding
        return (minValue: minValue, minY: minY, maxValue: maxValue, maxY: maxY)
    }

    private func firstHourDate() -> Date {
        let firstDate = glucose.first?.dateString ?? Date()
        return firstDate.dateTruncated(from: .minute)!
    }

    private func firstHourPosition(viewWidth: CGFloat) -> CGFloat {
        let firstDate = glucose.first?.dateString ?? Date()
        let firstHour = firstHourDate()

        let lastDeltaTime = firstHour.timeIntervalSince(firstDate)
        let oneSecondWidth = oneSecondStep(viewWidth: viewWidth)
        return oneSecondWidth * CGFloat(lastDeltaTime)
    }
}
