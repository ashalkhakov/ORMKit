/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMFactSentence.h"
#import "ORMConstraintSentence.h"

/* What the Fact Editor takes: sentences, read against the model and made
 * into what they say. */
@interface ORMSentenceEditor : NSObject
- (instancetype)initWithEditor:(ORMEditor *)editor;
@property (nonatomic, readonly, strong) ORMEditor *editor;

/* Makes what the sentence says, as one step: the object types and fact
 * types it names that the model lacks (placed on the diagram), then its
 * constraints. A sentence that is no constraint is taken as a fact type,
 * as the Fact Editor takes it. The ids of what was made. */
- (NSArray<NSString *> *)addFromSentence:(NSString *)text
                               onDiagram:(NSString *)diagramId
                                      at:(NSPoint)point
                                  reason:(NSString **)reason;
@end

@interface ORMSentenceEditor (ORMStatements)
/* What the verbalizer says of object types rather than as a constraint,
 * read back and made:
 *
 *   Person is an entity type.
 *   Rating is a value type.
 *   Each Male is a Person.
 *   Each Male is by definition a Person who is of Gender 'M'.
 *                                 the rule kept as Male's definition
 *   Enrolment is where Student enrolled in Course.
 *   This association with Amount and Currency provides the preferred
 *     identification scheme for Money.
 *   The possible values of VIN match the pattern '[A-HJ-NPR-Z0-9]{17}'.
 *
 * What it names that the model lacks is made as an entity type. An object
 * type the model has already is not made again: its id. nil, with no
 * reason, for a sentence that is none of these. */
- (NSArray<NSString *> *)addStatement:(NSString *)text
                            onDiagram:(NSString *)diagramId
                                   at:(NSPoint)point
                               reason:(NSString **)reason;

/* A schema as text, a sentence a line, each as -addFromSentence: takes
 * it, and lines that go on from the one before:
 *
 *   # Fill-ups                     a new diagram, for the lines after it
 *   Reference Mode: .id            the object type the line before named
 *   Portable data type: Numeric: Decimal(10, 2)
 *                                  the same
 *   Fact Type Name: ExchangeRate   the fact type the line before made
 *   * text                         the fact type the line before made is
 *                                  derived by the rule the text says;
 *                                  ** derived and stored, + partly
 *                                  derived, ++ partly and stored
 *   Query Name:                    a query: its outline, as ormtool query
 *   It is impossible that:         prints it, on the lines after, up to a
 *   ✓Branch                        blank line (ORMOutlineReader)
 *     + ...
 *   // ...                         a comment
 *
 * Each diagram is arranged at the end, as one step. NO when a line could
 * not be read, each such with its number and why ("12: ..."); the rest are
 * made. */
- (BOOL)addFromText:(NSString *)text failures:(NSArray<NSString *> **)failures;
@end

@interface ORMSentenceEditor (ORMFactSentences)
/* Makes what the sentence says: its new object types and the fact type,
 * placed on the diagram. The fact type's id. */
- (NSString *)addFactTypeFromSentence:(NSString *)text
                            onDiagram:(NSString *)diagramId
                                   at:(NSPoint)point
                               reason:(NSString **)reason;
@end
