/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCoreDataSync.h"

/* A Core Data model brought into ORM: reverse engineering, from the
 * logical model to the conceptual one, as Halpin and Bloesch set UML's
 * constructs against ORM's (a class an entity type, an attribute a fact
 * type, a Boolean attribute a unary, multiplicity uniqueness and mandatory
 * constraints, an association class an objectification).
 *
 *   Entity                      entity type
 *   unique required attribute   its reference mode (Person(.email))
 *   composite uniqueness        an external uniqueness, its identifier
 *                               when it has none
 *   attribute                   "Entity has Value": functional, mandatory
 *                               unless optional, the value type by name
 *   required Boolean            a unary: "isActive" is "Entity is active"
 *   Transformable               a value type mapped Transformable, of its
 *                               class
 *   relationship and inverse    a binary fact type, unique on each to-one
 *                               side, mandatory where required; a name
 *                               ending in the destination's is a
 *                               hyphen-bound reading ("Order has billing-
 *                               Address")
 *   join entity: to-one         an objectified fact type over the entities
 *   relationships only, unique  it joins, named as the entity, its other
 *   together                    attributes the objectification's facts
 *   parent entity               supertype; an abstract one is covered by
 *                               its subtypes (an inclusive-or)
 *
 * The mapping it makes (in the Entities style, so nothing is absorbed)
 * maps the result back to the same Core Data model: names the rules would
 * give otherwise are kept as the mapping's names, and the model is the
 * mapping's baseline, so what ORM cannot say (deletion rules, fetch
 * requests, configurations) stays as it was. */

@interface ORMEditor (ORMCoreDataImport)
/* Makes the Core Data model's ORM counterpart in this model, on a diagram
 * of its own (the model's only diagram, when that is empty), as one step,
 * with a mapping to the .xcdatamodeld at the path. The mapping's id; what
 * could not be said in ORM in the notes. */
- (NSString *)importCoreDataModel:(ORMCDModel *)model
                             path:(NSString *)path
                            notes:(NSArray<NSString *> **)notes
                           reason:(NSString **)reason;
@end
