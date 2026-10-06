/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMDeriver.h"
#import "ORMQuery.h"
#import "ORMQueryPlanner.h"
#import "ORMQueryInterpreter.h"
#import "ORMPopulationStore.h"
#import "ORMCoreDataMapping.h"
#import "ORMPath.h"
#import <CoreData/CoreData.h>

@interface ORMDerivedFact ()
@property (nonatomic, readwrite, strong) ORMFactType *factType;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, id> *players;
@end

@implementation ORMDerivedFact

- (BOOL)isOfInstances
{
	for (id player in [self.players allValues]) {
		if (![player isKindOfClass:[ORMInstance class]]) {
			return NO;
		}
	}
	return YES;
}

@end

/* The instance an instance is identified as: a subtype's with no
 * identifier of its own is its supertype's. */
static ORMInstance *
ORMIdentifiedInstance(ORMInstance *instance)
{
	while ([instance supertypeInstance] != nil && instance.objectType.preferredIdentifier == nil) {
		instance = [instance supertypeInstance];
	}
	return instance;
}

/* Whether a row's value is the instance, by what identifies it: a value
 * as such (a number numerically), an entity by its identifying values, a
 * list of them where there are several, in its preferred identifier's
 * order. */
static BOOL
ORMRowValueIs(id value, ORMInstance *instance)
{
	if (value == nil || value == [NSNull null] || instance == nil) {
		return NO;
	}
	instance = ORMIdentifiedInstance(instance);
	if (instance.value != nil) {
		if ([value isKindOfClass:[NSNumber class]]) {
			NSDecimalNumber *text = [NSDecimalNumber decimalNumberWithString:instance.value];
			return ![text isEqualToNumber:[NSDecimalNumber notANumber]]
			       && [text compare:[NSDecimalNumber decimalNumberWithDecimal:[(NSNumber *)value decimalValue]]]
			              == NSOrderedSame;
		}
		return [[value description] isEqualToString:instance.value];
	}
	NSArray *roles = [instance.objectType.preferredIdentifier allRoles];
	NSDictionary *identifying = [instance identifyingInstancesByRole];
	if ([roles count] == 0) {
		return NO;
	}
	if ([roles count] == 1) {
		return ORMRowValueIs(value, [identifying objectForKey:[[roles firstObject] identifier]]);
	}
	if (![value isKindOfClass:[NSArray class]] || [(NSArray *)value count] != [roles count]) {
		return NO;
	}
	for (NSUInteger i = 0; i < [roles count]; i++) {
		if (!ORMRowValueIs([(NSArray *)value objectAtIndex:i], [identifying objectForKey:[[roles objectAtIndex:i] identifier]])) {
			return NO;
		}
	}
	return YES;
}

@implementation ORMDeriver
{
	ORMCoreDataMapping *_mapping;
	NSMutableArray<NSString *> *_notes;
	NSDictionary<NSString *, NSArray<ORMDerivedFact *> *> *_facts;
}

- (instancetype)initWithModel:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping
{
	if ((self = [super init])) {
		_model = model;
		_mapping = mapping;
	}
	return self;
}

- (instancetype)initWithModel:(ORMModel *)model
{
	NSXMLDocument *document = [model.modelElement rootDocument];
	ORMCoreDataMapping *mapping = document != nil ? [[ORMCoreDataMapping mappingsOfDocument:document] firstObject] : nil;
	return [self initWithModel:model mapping:mapping];
}

- (NSArray<NSString *> *)notes
{
	[self derivedFacts];
	return [_notes copy];
}

- (void)note:(ORMQuery *)query text:(NSString *)text
{
	[_notes addObject:[NSString stringWithFormat:@"%@: %@", query.name, text]];
}

- (NSDictionary<NSString *, NSArray<ORMDerivedFact *> *> *)derivedFacts
{
	if (_facts != nil) {
		return _facts;
	}
	_notes = [NSMutableArray array];
	NSMutableArray *derivations = [NSMutableArray array];
	for (ORMQuery *query in [ORMQuery queriesInModel:_model]) {
		if (query.kind == ORMQueryDerivation && query.derivedFactType != nil) {
			[derivations addObject:query];
		}
	}
	NSMutableDictionary *facts = [NSMutableDictionary dictionary];
	_facts = facts;
	if ([derivations count] == 0) {
		return _facts;
	}
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_model mapping:_mapping];
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:_model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	if (context == nil) {
		for (ORMQuery *query in derivations) {
			[self note:query text:[NSString stringWithFormat:@"the population could not be stored: %@",
			                                                 error.localizedDescription ?: @"?"]];
		}
		return _facts;
	}
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:store.managedObjectModel];
	for (ORMQuery *query in derivations) {
		ORMFactType *fact = query.derivedFactType;
		NSArray *roles = [fact visibleRoles];
		ORMQueryPlan *plan = [planner planForQuery:query];
		if ([plan.notes count] > 0) {
			[self note:query text:[plan.notes componentsJoinedByString:@" "]];
			continue;
		}
		if ([plan.columns count] != [roles count]) {
			[self note:query text:[NSString stringWithFormat:@"it lists %lu, and \"%@\" has %lu roles.",
			                                                 (unsigned long)[plan.columns count],
			                                                 [[fact primaryReading] expandedText] ?: fact.name,
			                                                 (unsigned long)[roles count]]];
			continue;
		}
		__block ORMQueryResult *result = nil;
		__block NSError *failed = nil;
		[context performBlockAndWait:^{
			result = [interpreter executePlan:plan inContext:context error:&failed];
		}];
		if (result == nil) {
			[self note:query text:failed.localizedDescription ?: @"it could not be run."];
			continue;
		}
		NSMutableArray *derived = [NSMutableArray array];
		NSMutableSet *seen = [NSMutableSet set];
		for (NSArray *row in result.rows) {
			NSMutableDictionary *players = [NSMutableDictionary dictionary];
			NSMutableArray *key = [NSMutableArray array];
			for (NSUInteger i = 0; i < [roles count]; i++) {
				ORMRole *role = [roles objectAtIndex:i];
				id value = [row objectAtIndex:i];
				if (value == [NSNull null]) {
					players = nil;
					break;
				}
				id player = nil;
				for (ORMInstance *instance in [role.player instances]) {
					if (ORMRowValueIs(value, instance)) {
						player = instance;
						break;
					}
				}
				if (player == nil && role.player.kind == ORMValueType) {
					/* A value the population has no instance of. */
					player = [value description];
				}
				if (player == nil) {
					players = nil;
					break;
				}
				[players setObject:player forKey:role.identifier];
				[key addObject:[player isKindOfClass:[ORMInstance class]] ? [player identifier] : player];
			}
			if (players == nil || [seen containsObject:key]) {
				continue;
			}
			[seen addObject:key];
			ORMDerivedFact *each = [[ORMDerivedFact alloc] init];
			each.factType = fact;
			each.players = players;
			[derived addObject:each];
		}
		[facts setObject:derived forKey:fact.identifier];
	}
	return _facts;
}

@end
