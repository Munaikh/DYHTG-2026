import AlgorithmArenaCore
import Foundation

public enum MatchFixture: String, CaseIterable, Sendable {
  case lobby, practice, active, pendingFeedback, routeChoice, middleStandard, middleBonus
  case sharedThirdStandard, sharedThirdBonus, feedbackReleased, waitingFinish
  case finished, draw, incomplete, learningCheck, learningCheckAnswered
}

extension ArenaFixtures {
  public static func snapshot(_ fixture: MatchFixture, algorithm: AlgorithmKind) -> MatchSnapshot {
    let first = challengeID(.first, algorithm)
    let third = challengeID(.third, algorithm)
    let branch: RouteBranch? =
      switch fixture {
      case .lobby, .practice, .active, .routeChoice, .incomplete: nil
      case .middleBonus, .sharedThirdBonus: .bonus
      default: .standard
      }
    let middle: ChallengeSlot = branch == .bonus ? .bonusMiddle : .standardMiddle
    let pastMiddle = [
      .sharedThirdStandard, .sharedThirdBonus, .feedbackReleased, .waitingFinish,
      .finished, .draw, .learningCheck, .learningCheckAnswered,
    ].contains(fixture)
    let pastThird = [
      .feedbackReleased, .waitingFinish, .finished, .draw, .learningCheck, .learningCheckAnswered,
    ].contains(fixture)
    let selfFinished = [.waitingFinish, .finished, .draw, .learningCheck, .learningCheckAnswered]
      .contains(fixture)
    let bothFinished = fixture == .finished || fixture == .draw
    let firstSubmitted = ![.lobby, .practice, .active].contains(fixture)
    let firstReleased = firstSubmitted && ![.pendingFeedback, .routeChoice].contains(fixture)
    let phase: MatchPhase =
      switch fixture {
      case .lobby: .lobby
      case .practice: .practice
      case .waitingFinish, .learningCheck, .learningCheckAnswered: .awaitingFinish
      case .finished, .draw: .finished
      case .incomplete: .incomplete
      default: .active
      }
    let stage: PlayerStage =
      switch fixture {
      case .lobby: .atStart
      case .practice: .practice
      case .active: .challenge(challengeID: first)
      case .routeChoice, .incomplete: .choosingRoute
      case .pendingFeedback: .walking(target: "standard")
      case .middleStandard, .middleBonus: .challenge(challengeID: challengeID(middle, algorithm))
      case .sharedThirdStandard, .sharedThirdBonus: .challenge(challengeID: third)
      case .feedbackReleased: .walking(target: "finish")
      default: .finished
      }
    let availableSlot: ChallengeSlot? =
      switch fixture {
      case .practice: .practice
      case .active: .first
      case .middleStandard, .middleBonus: middle
      case .sharedThirdStandard, .sharedThirdBonus: .third
      case .learningCheck, .finished, .draw: .learningCheck
      default: nil
      }
    var submissions: [PrivateSubmission] = []
    var feedback: [FeedbackAvailability] = []
    var awards: [ScoreAward] = []
    var completed: [ChallengeID] = []
    var arrivals = [ConfirmedArrival(nodeID: "start", method: .location)]
    func addSubmission(_ slot: ChallengeSlot, released: Bool, commandID: UUID) {
      submissions.append(
        .init(
          challengeID: challengeID(slot, algorithm), commandID: commandID,
          answer: correctAnswer(slot, algorithm), acceptedAt: timestamp))
      if released {
        var content = Self.feedback(slot, algorithm)
        if fixture == .draw && content.answers.count == 2 {
          content = .init(
            challengeID: content.challengeID, correctAnswer: content.correctAnswer,
            explanation: content.explanation, workedSteps: content.workedSteps,
            trace: content.trace,
            answers: [
              content.answers[0],
              .init(
                playerID: opponentID, answer: content.correctAnswer,
                isCorrect: true, awardedPoints: challenge(slot, algorithm).maximumPoints),
            ])
        }
        feedback.append(.released(feedback: content))
      } else {
        feedback.append(.pending(challengeID: challengeID(slot, algorithm)))
      }
    }
    if fixture != .lobby && fixture != .practice {
      addSubmission(
        .practice, released: true,
        commandID: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!)
      arrivals.append(.init(nodeID: "first", method: .location))
    }
    if firstSubmitted {
      addSubmission(.first, released: firstReleased, commandID: submissionCommandID)
      completed.append(first)
      if firstReleased { awards.append(.init(slot: .first, points: 20)) }
    }
    if pastMiddle || fixture == .middleStandard || fixture == .middleBonus {
      arrivals.append(.init(nodeID: branch == .bonus ? "bonus" : "standard", method: .location))
    }
    if pastMiddle {
      addSubmission(
        middle, released: true, commandID: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
      )
      completed.append(challengeID(middle, algorithm))
      awards.append(.init(slot: middle, points: branch == .bonus ? 40 : 20))
      arrivals.append(.init(nodeID: "third", method: .location))
    }
    if pastThird {
      addSubmission(
        .third, released: true, commandID: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
      )
      completed.append(third)
      awards.append(.init(slot: .third, points: 20))
    }
    if selfFinished {
      arrivals.append(.init(nodeID: "finish", method: .organiserApproval))
      awards.append(.init(slot: nil, points: 20))
    }
    if fixture == .learningCheckAnswered {
      addSubmission(
        .learningCheck, released: true,
        commandID: UUID(uuidString: "00000000-0000-4000-8000-000000000005")!)
    }
    let opponentCorrect = fixture == .draw
    var opponentAwards: [ScoreAward] = []
    if firstReleased {
      opponentAwards.append(.init(slot: .first, points: opponentCorrect ? 20 : 0))
    }
    if pastMiddle { opponentAwards.append(.init(slot: .standardMiddle, points: 20)) }
    if pastThird { opponentAwards.append(.init(slot: .third, points: opponentCorrect ? 20 : 0)) }
    if bothFinished { opponentAwards.append(.init(slot: nil, points: 20)) }
    let ownScore = awards.reduce(0) { $0 + $1.points }
    let opponentScore = opponentAwards.reduce(0) { $0 + $1.points }
    let remaining =
      (firstSubmitted ? 0 : 20) + (pastMiddle ? 0 : (branch == .standard ? 20 : 40))
      + (pastThird ? 0 : 20) + (selfFinished ? 0 : 20)
    let opponentStage: PlayerStage =
      if fixture == .incomplete { .departed } else if bothFinished { .finished } else if pastThird {
        .walking(target: "finish")
      } else if pastMiddle { .challenge(challengeID: third) } else if firstReleased {
        .walking(target: "standard")
      } else if phase == .lobby { .atStart } else if phase == .practice { .practice } else {
        .challenge(challengeID: first)
      }
    let opponentArrivals: [ConfirmedArrival] =
      if bothFinished {
        ["start", "first", "standard", "third", "finish"].map {
          .init(nodeID: $0, method: .location)
        }
      } else if pastMiddle {
        ["start", "first", "standard", "third"].map { .init(nodeID: $0, method: .location) }
      } else if phase != .lobby && phase != .practice {
        ["start", "first"].map { .init(nodeID: $0, method: .location) }
      } else { [.init(nodeID: "start", method: .location)] }
    let opponentCompleted =
      (firstReleased ? [first] : [])
      + (pastMiddle ? [challengeID(.standardMiddle, algorithm)] : []) + (pastThird ? [third] : [])
    let players = [
      PlayerProgress(
        id: playerID, nickname: "Alex", algorithmConfirmed: true, ready: true, connection: .online,
        stage: stage, routeChoice: branch, arrivals: arrivals, completedChallengeIDs: completed,
        releasedScore: ownScore, pendingRewardMaximum: firstSubmitted && !firstReleased ? 20 : 0,
        remainingAvailablePoints: phase == .incomplete ? 0 : remaining),
      PlayerProgress(
        id: opponentID, nickname: "Sam", algorithmConfirmed: fixture != .lobby,
        ready: fixture != .lobby,
        connection: .online, stage: opponentStage,
        routeChoice: firstReleased && fixture != .incomplete ? .standard : nil,
        arrivals: opponentArrivals, completedChallengeIDs: opponentCompleted,
        releasedScore: opponentScore,
        pendingRewardMaximum: 0,
        remainingAvailablePoints: bothFinished || fixture == .incomplete
          ? 0
          : (firstReleased ? 0 : 20) + (pastMiddle ? 0 : (firstReleased ? 20 : 40))
            + (pastThird ? 0 : 20) + 20),
    ]
    let standings = [
      Standing(playerID: playerID, routeChoice: branch, score: ownScore, awards: awards),
      Standing(
        playerID: opponentID, routeChoice: players[1].routeChoice, score: opponentScore,
        awards: opponentAwards),
    ]
    let result: MatchResult? =
      switch fixture {
      case .finished: .winner(playerID: playerID, standings: standings)
      case .draw: .draw(standings: standings)
      case .incomplete: .incomplete(departedPlayerID: opponentID, standings: standings)
      default: nil
      }
    let navigation: NavigationState? =
      switch fixture {
      case .active: .init(nextStop: "first", edgeIDs: ["start-first"])
      case .pendingFeedback: .init(nextStop: "standard", edgeIDs: ["first-standard"])
      case .feedbackReleased: .init(nextStop: "finish", edgeIDs: ["third-finish"])
      default: nil
      }
    let revision =
      switch fixture {
      case .lobby: 1
      case .practice: 4
      case .active: 8
      case .routeChoice: 9
      case .pendingFeedback: 10
      case .middleStandard, .middleBonus: 14
      case .sharedThirdStandard, .sharedThirdBonus: 18
      case .feedbackReleased: 20
      case .waitingFinish, .learningCheck: 22
      case .learningCheckAnswered: 23
      case .finished, .draw: 25
      case .incomplete: 12
      }
    return .init(
      revision: revision, serverTime: timestamp,
      room: .init(
        matchID: matchID, roomCode: "ARENA1", creatorID: playerID, course: courseReference,
        algorithm: algorithm, phase: phase, players: players, result: result),
      viewer: .init(
        playerID: playerID, submissions: submissions, feedback: feedback,
        availableChallenges: availableSlot.map { [challenge($0, algorithm)] } ?? [],
        navigation: navigation,
        learningCheck: fixture == .learningCheckAnswered
          ? .init(
            challengeID: challengeID(.learningCheck, algorithm),
            firstAnswer: correctAnswer(.learningCheck, algorithm),
            answeredAt: timestamp, nodeCorrect: true, reasonCorrect: true) : nil))
  }

  public static func submissionCommand(_ algorithm: AlgorithmKind) -> MatchCommand {
    .init(
      id: submissionCommandID,
      scope: .match(matchID: matchID, course: courseReference, expectedRevision: 8),
      action: .submitAnswer(
        challengeID: challengeID(.first, algorithm), answer: correctAnswer(.first, algorithm)))
  }

  public static func reconnect(_ algorithm: AlgorithmKind) -> ReconnectState {
    .init(
      lastConfirmedSnapshot: snapshot(.active, algorithm: algorithm),
      pendingCommand: submissionCommand(algorithm))
  }
}
