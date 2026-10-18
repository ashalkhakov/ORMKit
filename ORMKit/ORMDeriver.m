/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMDeriver.h"
#import "ORMQuery.h"
#import "ORMQueryPlanner.h"
#if __has_include(<ORMRuntime/ORMRuntime.h>)
#import <ORMRuntime/ORMRuntime.h>
#else
#import "ORMRuntime.h"
#endif
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

/* The values that identify an instance, in its preferred identifier's
 * order, each part's own taken apart the same way: a value type
 * instance's value; an entity's identifying instances', or, for an
 * objectifying type's, its fact's players in those roles. nil where one
 * is missing. */
static NSArray<NSString *> *
ORMIdentifyingValues(ORMInstance *instance)
{
	instance = ORMIdentifiedInstance(instance);
	if (instance.value != nil) {
		return @[ instance.value ];
	}
	NSArray *roles = [instance.objectType.preferredIdentifier allRoles];
	NSDictionary *identifying = [instance identifyingInstancesByRole];
	NSDictionary *players = [[instance objectifiedInstance] instancesByRole];
	NSMutableArray *values = [NSMutableArray array];
	for (ORMRole *role in roles) {
		ORMInstance *part = [identifying objectForKey:role.identifier] ?: [players objectForKey:role.identifier];
		NSArray *own = part != nil ? ORMIdentifyingValues(part) : nil;
		if (own == nil) {
			return nil;
		}
		[values addObjectsFromArray:own];
	}
	return [values count] > 0 ? values : nil;
}

/* A row's value taken apart: its parts' values, in order. */
static void
ORMLeafValues(id value, NSMutableArray *into)
{
	if ([value isKindOfClass:[NSArray class]]) {
		for (id part in (NSArray *)value) {
			ORMLeafValues(part, into);
		}
	} else {
		[into addObject:value ?: [NSNull null]];
	}
}

/* Whether the number is a Boolean, as Core Data gives one. */
static BOOL
ORMIsBoolean(id value)
{
	return [value isKindOfClass:[NSNumber class]] && strcmp([(NSNumber *)value objCType], @encode(char)) == 0;
}

/* A row's value as a sample writes it: a Boolean true or false, a date
 * a day or a moment, UTC. */
static NSString *
ORMTextOfValue(id value)
{
	if (ORMIsBoolean(value)) {
		return [value boolValue] ? @"true" : @"false";
	}
	if ([value isKindOfClass:[NSDate class]]) {
		NSDateFormatter *dates = [[NSDateFormatter alloc] init];
		[dates setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
		[dates setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
		[dates setDateFormat:@"HH:mm:ss"];
		BOOL day = [[dates stringFromDate:value] isEqualToString:@"00:00:00"];
		[dates setDateFormat:day ? @"yyyy-MM-dd" : @"yyyy-MM-dd'T'HH:mm:ss"];
		return [dates stringFromDate:value];
	}
	return [value description];
}

/* Whether a row's value is the text: a number numerically, a Boolean or a
 * date as the store reads the text. */
static BOOL
ORMValueIsText(id value, NSString *text)
{
	if (value == [NSNull null]) {
		return NO;
	}
	if (ORMIsBoolean(value)) {
		NSString *lower = [[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
		NSArray *said = [value boolValue] ? @[ @"true", @"yes", @"1" ] : @[ @"false", @"no", @"0" ];
		return [said containsObject:lower];
	}
	if ([value isKindOfClass:[NSDate class]]) {
		NSDate *date = [ORMPopulationStore dateOfText:text];
		return date != nil && [date isEqualToDate:value];
	}
	if ([value isKindOfClass:[NSNumber class]]) {
		NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:text];
		return ![number isEqualToNumber:[NSDecimalNumber notANumber]]
		       && [number compare:[NSDecimalNumber decimalNumberWithDecimal:[(NSNumber *)value decimalValue]]]
		              == NSOrderedSame;
	}
	return [ORMTextOfValue(value) isEqualToString:text];
}

/* Whether a row's value is the instance, by what identifies it: a value
 * as such, an entity by its identifying values, a list of them where
 * there are several, parts of parts in line. */
static BOOL
ORMRowValueIs(id value, ORMInstance *instance)
{
	if (value == nil || value == [NSNull null] || instance == nil) {
		return NO;
	}
	NSArray *texts = ORMIdentifyingValues(instance);
	NSMutableArray *leaves = [NSMutableArray array];
	ORMLeafValues(value, leaves);
	if (texts == nil || [texts count] != [leaves count]) {
		return NO;
	}
	for (NSUInteger i = 0; i < [texts count]; i++) {
		if (!ORMValueIsText([leaves objectAtIndex:i], [texts objectAtIndex:i])) {
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
	ORMCoreDataMapping *mapping = [model.coreDataMappings firstObject];
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

/* A row's parts as the instances or values that identify an instance of
 * the role's player: @{ part role id: instance or text }; nil where an
 * entity part has no instance. */
- (NSDictionary *)partsOf:(NSArray *)values role:(ORMRole *)role
{
	NSArray *partRoles = [ORMQuery partRolesOf:role.player];
	NSMutableDictionary *parts = [NSMutableDictionary dictionary];
	for (NSUInteger i = 0; i < [partRoles count] && i < [values count]; i++) {
		ORMRole *part = [partRoles objectAtIndex:i];
		id found = nil;
		for (ORMInstance *instance in [part.player instances]) {
			if (ORMRowValueIs([values objectAtIndex:i], instance)) {
				found = instance;
				break;
			}
		}
		if (found == nil && part.player.kind == ORMValueType) {
			found = ORMTextOfValue([values objectAtIndex:i]);
		}
		if (found == nil) {
			return nil;
		}
		[parts setObject:found forKey:part.identifier];
	}
	return parts;
}

- (NSDictionary<NSString *, NSArray<ORMDerivedFact *> *> *)derivedFacts
{
	if (_facts != nil) {
		return _facts;
	}
	_notes = [NSMutableArray array];
	NSArray *derivations = [ORMQuery derivationsInModel:_model];
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
		/* Each role's columns in the row, by their nodes: one, or a part
		 * each for a player of several identifying values. */
		NSArray *groups = [query derivedColumnGroups];
		NSMutableArray *at = [NSMutableArray array];
		NSUInteger listed = 0;
		for (NSArray *group in groups) {
			NSMutableArray *indexes = [NSMutableArray array];
			for (ORMQueryNode *node in group) {
				ORMPlanColumn *column = [plan columnOfNode:node.identifier];
				NSUInteger index = column != nil ? [plan.columns indexOfObject:column] : NSNotFound;
				if (index != NSNotFound) {
					[indexes addObject:@(index)];
				}
			}
			if ([indexes count] == [group count]) {
				[at addObject:indexes];
				listed += [indexes count];
			}
		}
		if ([plan.columns count] != listed || [at count] != [roles count]) {
			[self note:query text:[NSString stringWithFormat:@"it lists %lu, and \"%@\" has %lu roles.",
			                                                 (unsigned long)[plan.columns count],
			                                                 [fact displayText],
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
				NSArray *indexes = [at objectAtIndex:i];
				NSMutableArray *parts = [NSMutableArray array];
				for (NSNumber *index in indexes) {
					[parts addObject:[row objectAtIndex:[index unsignedIntegerValue]]];
				}
				id value = [parts count] == 1 ? [parts firstObject] : parts;
				if ([parts containsObject:[NSNull null]]) {
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
					player = ORMTextOfValue(value);
				}
				if (player == nil && [parts count] > 1) {
					/* An instance of several values none is yet: its parts, an
					 * instance each, or a value's text. */
					player = [self partsOf:parts role:role];
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
