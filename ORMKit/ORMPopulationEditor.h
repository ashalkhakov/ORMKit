/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditor.h"

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
@end
