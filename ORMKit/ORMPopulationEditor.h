/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditor.h"

@class ORMInstance;

/* Instances to add to a model's sample population, as one change: values,
 * entity instances by what identifies them, subtype instances, and facts.
 * Each is named by the id its element will have (or an instance's the
 * model has already), so later ones refer to earlier ones. Made by hand or
 * by ORMPopulationGenerator; written by ORMPopulationEditor. */
@interface ORMSamplePopulation : NSObject
/* An instance of the value type: the one of that value this population or
 * the model has, or a new one. Its id. */
- (NSString *)value:(NSString *)text of:(NSString *)valueTypeId;
/* An instance of the entity type identified by the instances playing its
 * preferred identifier's roles (by role id): the one so identified this
 * population has, or a new one. Its id. */
- (NSString *)instanceOf:(NSString *)entityTypeId identifiedBy:(NSDictionary<NSString *, NSString *> *)instancesByRole;
/* An instance of the subtype that is the supertype's instance. Its id. */
- (NSString *)instanceOf:(NSString *)subtypeId supertypeInstance:(NSString *)instanceId;
/* A fact of the fact type: the instance playing each role, by role id. A
 * unary's names its one role (its implicit truth value is added). Its id. */
- (NSString *)factOf:(NSString *)factTypeId players:(NSDictionary<NSString *, NSString *> *)instancesByRole;
/* The same, with the id it is to have: for an instance to objectify it
 * before it is made. */
- (void)factOf:(NSString *)factTypeId players:(NSDictionary<NSString *, NSString *> *)instancesByRole
    identifier:(NSString *)identifier;
/* The instance of an objectifying entity type that is the fact (of the fact
 * type it objectifies, made here or in the model). Its id. */
- (NSString *)instanceOf:(NSString *)entityTypeId objectifying:(NSString *)factInstanceId;
/* The same, for a type identified otherwise than by the fact it
 * objectifies: also by the instances playing its preferred identifier's
 * roles. */
- (NSString *)instanceOf:(NSString *)entityTypeId
            objectifying:(NSString *)factInstanceId
            identifiedBy:(NSDictionary<NSString *, NSString *> *)instancesByRole;
- (BOOL)isEmpty;
@end

/* The sample population, written as NORMA writes it: an instance under its
 * object type, a fact instance under its fact type, and each instance
 * playing a role a role instance under the role. Usually reached as an
 * editor's populationEditor. */
@interface ORMPopulationEditor : NSObject
- (instancetype)initWithEditor:(ORMEditor *)editor;
@property (nonatomic, readonly, weak) ORMEditor *editor;

/* Adds the instances, as one change; refused, with nothing added, when one
 * names what is not there or is not of the type its role's player is. */
- (BOOL)addPopulation:(ORMSamplePopulation *)population reason:(NSString **)reason;
/* Removes every instance, fact instance and role instance: the model with
 * no population. */
- (void)removePopulation;

/* One fact or instance at a time, as a table of a population edits it
 * (docs/WINDOW.md). Each is one change. An instance is named by its text,
 * as the table shows it: a value type's value; an entity type's reference
 * mode's value (a subtype's, its supertype's); the instance so named the
 * model has, or a new one. */

/* The instance of the object type named so, into the population: its id.
 * nil, and why, for one named wrongly: the wrong number of values for
 * what identifies it, or one an objectified fact type is. */
- (NSString *)instanceOf:(NSString *)objectTypeId
                   named:(NSString *)text
                    into:(ORMSamplePopulation *)population
                  reason:(NSString **)reason;
/* A fact of the fact type, the player of each role (by id) named. Its id. */
- (NSString *)addFactOf:(NSString *)factTypeId named:(NSDictionary<NSString *, NSString *> *)textsByRole
                 reason:(NSString **)reason;
/* The fact, and its role instances, removed; refused when an instance of
 * an objectifying type is the fact. */
- (BOOL)removeFact:(NSString *)factInstanceId reason:(NSString **)reason;
/* The fact with the role's player named anew: the fact replaced, the
 * others' players kept. The new fact's id. */
- (NSString *)setPlayer:(NSString *)text ofRole:(NSString *)roleId inFact:(NSString *)factInstanceId
                 reason:(NSString **)reason;
/* An instance of the object type, named so. Its id. */
- (NSString *)addInstanceOf:(NSString *)objectTypeId named:(NSString *)text reason:(NSString **)reason;
/* An instance of an entity type identified by several values, each named
 * by the role of its preferred identifier it plays (by id). Its id. */
- (NSString *)addInstanceOf:(NSString *)objectTypeId
                namedByRole:(NSDictionary<NSString *, NSString *> *)textsByRole
                     reason:(NSString **)reason;
/* The roles an instance of the entity type is named by when more than
 * one value identifies it: its preferred identifier's (its supertype's,
 * for a subtype identified as that is), in order; empty otherwise. */
- (NSArray<ORMRole *> *)compositeRolesOf:(NSString *)objectTypeId;
/* What an instance is named, as a table shows it and the methods above
 * read it back: a value as it is; an entity by the values identifying it,
 * in its preferred identifier's order, joined by ", "; a part that is
 * itself named so in parentheses, and one with a comma, a parenthesis or a
 * quote in quotes ('O''Neil'); a subtype's as its supertype's. */
- (NSString *)nameOf:(ORMInstance *)instance;
/* The instance removed, and the role instances that identify it; refused
 * while a fact has it play a role, or it identifies or is another. */
- (BOOL)removeInstance:(NSString *)instanceId reason:(NSString **)reason;
@end
