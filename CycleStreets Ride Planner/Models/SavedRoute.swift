//
//  SavedRoute.swift
//  CycleStreets Ride Planner
//

import Foundation

struct SavedRoute: Codable, Identifiable, Equatable {
    let id: UUID
    let journeyID: Int
    var name: String
    let plan: RoutePlan
    let distanceMetres: Int
    let timeSeconds: Int
    let savedAt: Date

    init(id: UUID = UUID(), journeyID: Int, name: String, plan: RoutePlan,
         distanceMetres: Int, timeSeconds: Int, savedAt: Date) {
        self.id = id
        self.journeyID = journeyID
        self.name = name
        self.plan = plan
        self.distanceMetres = distanceMetres
        self.timeSeconds = timeSeconds
        self.savedAt = savedAt
    }
}

extension Journey {
    func asSavedRoute(name: String? = nil) -> SavedRoute {
        SavedRoute(journeyID: number, name: name ?? "Route \(number)",
                   plan: plan, distanceMetres: lengthMetres,
                   timeSeconds: timeSeconds, savedAt: Date())
    }
}
