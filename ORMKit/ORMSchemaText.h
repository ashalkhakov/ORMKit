/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditor.h"

/* A model as schema text: a statement a line, as the verbalizer says it,
 * and as -[ORMSentenceEditor addFromText:failures:] reads it back. It is a
 * listing written from the model (ormtool forml), not a source: the model
 * is the .orm, changed in ORMDesigner or by applying text to it (ormtool
 * apply, which reads these lines and removes what a "- " line says).
 *
 *   # Fill-ups                      a diagram, and what is first shown on it
 *   // ...                          the note of what the next line says
 *   Station is an entity type.      an object type, with its reference mode,
 *   Reference Mode: .name           data type and possible values
 *   Reference data: Fuel            its instances, when they are reference
 *                                   data (a subtype's after its subtyping)
 *   Each FillUp is a MeteredEvent.  subtyping, or its definition
 *   FillUp was at Station           a fact type, its role names "(as X)"
 *                                   and other readings after " / "
 *   Fact Type Name: ExchangeRate    its own name
 *   ++ text                         its derivation note (* derived, **
 *                                   derived and stored, + partly, ++ partly
 *                                   and stored)
 *   Each FillUp was at exactly one Station.
 *                                   its constraints
 *   Reference data: km, 1           its facts, when they are reference data
 *   For each Quantity and ...       a constraint over several fact types
 *   Query Name:                     a query, its outline (ORMQuery's
 *   ✓FillUp ...                     outlineText) up to a blank line
 *
 * A section is a diagram, in the model's order; in it, what the diagram
 * shows first, in the order of its shapes. What a statement names is said
 * before it: a fact type after its players, a constraint after its fact
 * types, a query after what it goes through and derives, where nothing
 * else places it. So the text reads back into the same model. */

typedef NS_ENUM(NSInteger, ORMSchemaLineKind) {
	ORMSchemaBlank,
	/* "# People and vehicles": a diagram. */
	ORMSchemaHeading,
	/* "// ...": a note of what follows; the text's own header has none. */
	ORMSchemaComment,
	/* "Vehicle is an entity type.", "Each Event is a Record." */
	ORMSchemaObjectType,
	/* "Reference Mode: .id", "Portable data type: ...", "X is independent." */
	ORMSchemaDetail,
	/* "The possible values of Year are at least 1886." */
	ORMSchemaValues,
	/* "Vehicle is owned by User", "VehicleDriver is where User drives Vehicle." */
	ORMSchemaFactType,
	/* "Fact Type Name: ExchangeRate" */
	ORMSchemaFactTypeName,
	/* "++ A service's: ..." */
	ORMSchemaDerivation,
	ORMSchemaConstraint,
	/* "Reference data: km, 1" */
	ORMSchemaReferenceData,
	/* "Query Name:" */
	ORMSchemaQuery,
	/* A line of a query's outline. */
	ORMSchemaOutline,
};

@interface ORMSchemaLine : NSObject
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly) ORMSchemaLineKind kind;
/* What the line says, by id: the object type, the subtype fact type, the
 * fact type, the constraints (a mandatory said with a uniqueness as
 * "exactly one" too; one said under its fact type, the fact type's id
 * last), the fact or instance of reference data, the query, the diagram; a comment,
 * the element it is the note of. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *elementIds;
@end

@interface ORMSchemaText : NSObject
- (instancetype)initWithEditor:(ORMEditor *)editor;
@property (nonatomic, readonly, strong) ORMEditor *editor;
/* The lines, without the header. */
- (NSArray<ORMSchemaLine *> *)lines;
/* The header (a comment saying what the text is, from what file) and the
 * lines, each ending in a newline. */
- (NSString *)textFromFile:(NSString *)fileName;

/* A line as a statement is compared: trimmed, without its full stop, its
 * spaces single. */
+ (NSString *)comparableLine:(NSString *)line;
@end
