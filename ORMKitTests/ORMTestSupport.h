/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <XCTest/XCTest.h>
#if __has_include(<ORMKit/ORMKit.h>)
#import <ORMKit/ORMKit.h>
#else
#import "ORMKit.h"
#endif

/* What every ORMKit test shares: the fixtures, found beside this file, so
 * the tests run from a source tree on both platforms. */
@interface ORMTestCase : XCTestCase
/* Fixtures/<name>'s bytes. */
- (NSData *)fixtureData:(NSString *)name;
/* Fixtures/<name> parsed; fails the test when it cannot be. */
- (NSXMLDocument *)fixtureDocument:(NSString *)name;
/* An editor on a new model, with an undo manager that does not group by
 * event: each operation is its own step. */
- (ORMEditor *)newEditor;
@property (nonatomic, readonly, strong) NSUndoManager *undoManager;
/* The real NORMA files: written by NORMA itself, so they say what NORMA's
 * derived data and layout are. StockMate is from a recent NORMA; the
 * ActiveFacts examples from NORMA builds of 2008 to 2015. */
- (NSArray<NSString *> *)normaFixtures;
/* "ActiveFacts/Address.orm", ...: Clifford Heath's examples. */
- (NSArray<NSString *> *)activeFactsFixtures;
@end

