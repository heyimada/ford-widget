import Foundation

/// Display names for the `indicators` keys the car reports; unknown keys fall back to a de-camelCased title.
enum WarningNames {
    private static let table: [String: (title: String, symbol: String)] = [
        "adaptiveCruiseControl": ("Adaptive cruise control", "gauge.with.dots.needle.67percent"),
        "airFilterMinder": ("Air filter service", "wrench.and.screwdriver"),
        "airSuspensionRideControlFault": ("Air suspension fault", "exclamationmark.triangle"),
        "allWheelDriveDisabled": ("All-wheel drive disabled", "exclamationmark.triangle"),
        "antiTheft": ("Anti-theft", "lock.trianglebadge.exclamationmark"),
        "antilockBrake": ("Anti-lock brakes", "exclamationmark.brakesignal"),
        "blindSpotDetection": ("Blind spot detection", "car.side.rear.and.collision.and.car.side.front"),
        "brakeWarning": ("Brake warning", "exclamationmark.brakesignal"),
        "chargeSystemFault": ("Charging system fault", "minus.plus.batteryblock"),
        "checkFuelCap": ("Check fuel cap", "fuelpump"),
        "checkFuelFillInlet": ("Check fuel filler", "fuelpump"),
        "dieselEngineIdleShutdown": ("Engine idle shutdown", "engine.combustion"),
        "dieselEngineWarning": ("Diesel engine warning", "engine.combustion"),
        "dieselExhaustFluidLow": ("Exhaust fluid low", "drop"),
        "dieselExhaustFluidSystemFault": ("Exhaust fluid system fault", "drop"),
        "dieselExhaustOverTemp": ("Exhaust too hot", "thermometer.high"),
        "dieselParticulateFilter": ("Particulate filter", "aqi.medium"),
        "dieselPreHeat": ("Glow plugs heating", "thermometer.medium"),
        "electricTrailerBrakeConnection": ("Trailer brake connection", "exclamationmark.triangle"),
        "electronicParkingBrakeWarning": ("Parking brake", "parkingsign.circle"),
        "engineCoolantOverTemp": ("Coolant overheating", "thermometer.high"),
        "fastenSeatBeltWarning": ("Fasten seat belt", "person.fill.checkmark"),
        "forwardCollisionWarning": ("Forward collision warning", "car.side.front.and.collision.and.car.side.rear"),
        "fuelDoorOpen": ("Fuel door open", "fuelpump"),
        "gasParticulateFilterWarning": ("Particulate filter", "aqi.medium"),
        "genericABSFaultWarning": ("ABS fault", "exclamationmark.brakesignal"),
        "hevHazard": ("Hybrid system hazard", "bolt.trianglebadge.exclamationmark"),
        "hillDescentControlFault": ("Hill descent control fault", "exclamationmark.triangle"),
        "hillStartAssistWarning": ("Hill start assist", "exclamationmark.triangle"),
        "laneKeepingAid": ("Lane keeping aid", "car.top.lane.dashed.badge.steeringwheel"),
        "lightingSystemFailure": ("Lighting system failure", "lightbulb.slash"),
        "lowBrakeFluid": ("Low brake fluid", "exclamationmark.brakesignal"),
        "lowEngineOilPressure": ("Low oil pressure", "oilcan"),
        "lowFuel": ("Low fuel", "fuelpump"),
        "lowWasherFluid": ("Low washer fluid", "drop"),
        "malfunctionIndicator": ("Check engine", "engine.combustion"),
        "parkAidMalfunction": ("Parking aid fault", "parkingsign"),
        "passiveEntryPassiveStart": ("Keyless entry and start", "key"),
        "powertrainMalfunction": ("Powertrain fault", "engine.combustion"),
        "restraintsIndicatorWarning": ("Airbag and restraints", "person.fill.xmark"),
        "serviceSteering": ("Steering service", "steeringwheel"),
        "startStopEngineWarning": ("Auto start-stop", "engine.combustion"),
        "tirePressureMonitorSystemWarning": ("Tire pressure", "tirepressure"),
        "tractionControlDisabled": ("Traction control off", "car.rear.road.lane"),
        "tractionControlEvent": ("Traction control active", "car.rear.road.lane"),
        "waterInFuel": ("Water in fuel", "drop.triangle"),
    ]

    static func title(for key: String) -> String {
        table[key]?.title ?? deCamelCased(key)
    }

    static func symbol(for key: String) -> String {
        table[key]?.symbol ?? "exclamationmark.triangle"
    }

    static func deCamelCased(_ key: String) -> String {
        var words: [String] = []
        var word = ""
        for character in key {
            if character.isUppercase, !word.isEmpty, !(word.last?.isUppercase ?? false) {
                words.append(word)
                word = ""
            }
            word.append(character)
        }
        if !word.isEmpty { words.append(word) }
        guard let first = words.first else { return key }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst().map { $0.lowercased() }).joined(separator: " ")
    }
}
