import XCTest

@MainActor
private protocol _MainActorXCTestCase {}

extension XCTestCase: _MainActorXCTestCase {}
