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
 * derived data and layout are, and normalizing them changes nothing.
 * StockMate is from a recent NORMA; the ActiveFacts examples from NORMA
 * builds of 2008 to 2015; NORMA's own samples and metamodels from its
 * repository. */
- (NSArray<NSString *> *)normaFixtures;
/* "ActiveFacts/Address.orm", ...: Clifford Heath's examples. */
- (NSArray<NSString *> *)activeFactsFixtures;
/* The .orm files under a fixtures directory, at any depth, sorted. */
- (NSArray<NSString *> *)fixturesUnder:(NSString *)directory;
/* Every file NORMA wrote: the above, and NORMA's own test suites, whose
 * 2006 and 2007 builds wrote derived data in ways NORMA has since
 * dropped; those are read and written back byte for byte, but not
 * normalized. */
- (NSArray<NSString *> *)allNormaFiles;
@end

