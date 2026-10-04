/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <ORMKit/ORMKit.h>
#include <stdio.h>

/* WorkMate's ORM2 model, reverse-engineered from the WorkMate database's
 * tables: what ORMKitTests/Fixtures/WorkMate.orm is made by.
 *
 *   xcodebuild -workspace ORMKit.xcworkspace -scheme ORMKit -derivedDataPath /tmp/ormkit build
 *   P=/tmp/ormkit/Build/Products/Debug
 *   clang -fobjc-arc -fmodules -F$P -framework ORMKit -Wl,-rpath,$P Tools/fixtures/workmate.m -o /tmp/workmate
 *   /tmp/workmate ORMKitTests/Fixtures/WorkMate.orm */

static ORMEditor *E;
static ORMSentenceEditor *sentences;
static int failures;

static void
check(BOOL ok, NSString *what, NSString *reason)
{
	if (!ok) {
		failures++;
		fprintf(stderr, "FAILED %s: %s\n", what.UTF8String, reason.UTF8String ?: "");
	}
}

static NSString *
diagram(NSString *name)
{
	for (ORMDiagram *d in E.model.diagrams) {
		if ([d.name isEqualToString:name]) {
			return d.identifier;
		}
	}
	return nil;
}

/* "u" unique, "m" mandatory, per role in the sentence's order. */
static NSArray<NSString *> *
fact(NSString *diagramName, NSString *sentence, NSArray<NSString *> *flags)
{
	NSString *reason = nil;
	NSString *f = [sentences addFactTypeFromSentence:sentence onDiagram:diagram(diagramName) at:ORMAutomaticPlacement reason:&reason];
	check(f != nil, sentence, reason);
	NSMutableArray *ids = [NSMutableArray array];
	NSArray *roles = [[E.model elementWithId:f] visibleRoles];
	for (NSUInteger i = 0; i < [roles count]; i++) {
		NSString *role = [roles[i] identifier];
		[ids addObject:role];
		NSString *flag = i < [flags count] ? flags[i] : @"";
		if ([flag containsString:@"u"]) {
			check([E.constraintEditor setUnique:YES role:role reason:&reason], [sentence stringByAppendingString:@" unique"], reason);
		}
		if ([flag containsString:@"m"]) {
			check([E.constraintEditor setMandatory:YES role:role reason:&reason], [sentence stringByAppendingString:@" mandatory"], reason);
		}
	}
	return ids;
}

static void
dataType(NSString *name, NSString *type, NSInteger length, NSInteger scale)
{
	NSString *reason = nil;
	ORMObjectType *t = [E.model objectTypeNamed:name];
	check(t != nil, name, @"no such object type");
	check([E.objectTypeEditor setDataType:type length:length scale:scale of:t.identifier reason:&reason], name, reason);
}

static void
external(NSArray<NSString *> *roles, NSString *what)
{
	NSString *reason = nil;
	NSString *c = [E.constraintEditor addUniquenessConstraintOverRoles:roles reason:&reason];
	check(c != nil, what, reason);
	ORMConstraint *constraint = [E.model elementWithId:c];
	for (ORMFactType *f in [constraint factTypes]) {
		for (ORMDiagram *d in E.model.diagrams) {
			if ([d shapeForSubject:f.identifier] != nil) {
				[E.diagramEditor placeElement:c onDiagram:d.identifier at:ORMAutomaticPlacement];
				return;
			}
		}
	}
}

static void
roleName(NSString *role, NSString *name)
{
	NSString *reason = nil;
	check([E.elementEditor rename:role to:name reason:&reason], name, reason);
}

int
main(int argc, char **argv)
{
	@autoreleasepool {
		E = [[ORMEditor alloc] initWithDocument:[ORMEditor newDocumentNamed:@"WorkMate"] undoManager:nil];
		sentences = [[ORMSentenceEditor alloc] initWithEditor:E];
		NSString *first = [[E.model.diagrams firstObject] identifier];
		[E.elementEditor rename:first to:@"Sites and Accounts" reason:NULL];
		[E.diagramEditor addDiagramNamed:@"Equipment"];
		[E.diagramEditor addDiagramNamed:@"Meters"];
		NSString *S = @"Sites and Accounts", *Q = @"Equipment", *M = @"Meters";
		NSArray *u = @[ @"um" ], *um = @[ @"um", @"u" ], *o = @[ @"u" ];

		/* Site */
		fact(S, @"Site(.Id) has SiteName()", um);
		fact(S, @"Site is active", @[]);
		/* Account */
		fact(S, @"Account(.Id) has EmailAddress()", um);
		fact(S, @"Account belongs to Site", u);
		fact(S, @"Account has FullName()", u);
		fact(S, @"Account is active", @[]);
		/* Location: named uniquely within its site. */
		NSArray *locationSite = fact(S, @"Location(.Id) is at Site", u);
		NSArray *locationName = fact(S, @"Location has LocationName()", u);
		external(@[ locationSite[1], locationName[1] ], @"Location's site and name");
		fact(S, @"Location is active", @[]);
		/* MeterGroup */
		NSArray *groupSite = fact(S, @"MeterGroup(.Id) is at Site", u);
		NSArray *groupName = fact(M, @"MeterGroup has MeterGroupName()", u);
		external(@[ groupSite[1], groupName[1] ], @"MeterGroup's site and name");
		fact(M, @"MeterGroup is active", @[]);

		/* Manufacturer, Equipment, EquipmentType */
		fact(Q, @"Manufacturer(.Id) has ManufacturerName()", um);
		NSArray *made = fact(Q, @"Equipment(.Id) is made by Manufacturer", u);
		NSArray *model = fact(Q, @"Equipment has ModelName()", u);
		external(@[ made[1], model[1] ], @"Equipment's manufacturer and model");
		fact(Q, @"Equipment is of EquipmentType(.Id)", o);
		fact(Q, @"EquipmentType has EquipmentTypeName()", u);
		NSArray *parent = fact(Q, @"EquipmentType is a kind of EquipmentType", o);
		roleName(parent[1], @"parent");
		NSString *reason = nil;
		NSString *ring = [E.constraintEditor addRingConstraint:ORMRingAcyclic overRoles:parent reason:&reason];
		check(ring != nil, @"acyclic equipment types", reason);
		[E.diagramEditor placeElement:ring onDiagram:diagram(Q) at:ORMAutomaticPlacement];
		/* EquipmentUnit: named uniquely within its location. */
		NSArray *unitLocation = fact(Q, @"EquipmentUnit(.Id) is at Location", u);
		fact(Q, @"EquipmentUnit is of Equipment", u);
		fact(Q, @"EquipmentUnit has SerialNumber()", o);
		fact(Q, @"EquipmentUnit was manufactured on Date()", o);
		NSArray *unitName = fact(Q, @"EquipmentUnit has EquipmentUnitName()", u);
		external(@[ unitLocation[1], unitName[1] ], @"EquipmentUnit's location and name");
		fact(Q, @"EquipmentUnit was purchased on Date", o);
		fact(Q, @"EquipmentUnit cost Money()", o);
		fact(Q, @"EquipmentUnit was commissioned at Moment()", u);
		/* PMP: a preventive maintenance plan. */
		fact(Q, @"PMP(.Id) is for Equipment", u);
		fact(Q, @"PMP recurs by RecurrencePattern()", o);
		fact(Q, @"PMP has Instructions()", u);
		fact(Q, @"PMP has instructions in- MimeType()", u);
		/* WorkOrder */
		fact(Q, @"WorkOrder(.Nr) results from PMP", o);
		NSArray *requested = fact(Q, @"WorkOrder was requested by Account", u);
		roleName(requested[1], @"requestor");
		NSArray *assigned = fact(Q, @"WorkOrder is assigned to Account", o);
		roleName(assigned[1], @"assignee");
		fact(Q, @"WorkOrder has WorkOrderStatus()", u);
		fact(Q, @"WorkOrder is for EquipmentUnit", u);
		fact(Q, @"WorkOrder has Notes()", o);
		fact(Q, @"WorkOrder has ScheduleInfo()", u);

		/* MeterType, Meter, MeterReading */
		fact(M, @"MeterType(.Id) has MeterTypeName()", um);
		fact(M, @"MeterType is measured in UnitOfMeasure()", u);
		fact(M, @"MeterType is specific to Site", o);
		fact(M, @"Meter(.Id) is of MeterType", u);
		NSArray *owner = fact(M, @"Meter is owned by Account", u);
		roleName(owner[1], @"owner");
		NSArray *meterGroup = fact(M, @"Meter belongs to MeterGroup", u);
		NSArray *meterName = fact(M, @"Meter has MeterName()", u);
		external(@[ meterGroup[1], meterName[1] ], @"Meter's group and name");
		fact(M, @"Meter counts in Direction()", o);
		NSArray *start = fact(M, @"Meter starts at Quantity()", o);
		roleName(start[1], @"startQty");
		fact(M, @"Meter has MeterNumber()", o);
		fact(M, @"Meter has Description()", o);
		fact(M, @"Meter is active", @[]);
		fact(M, @"MeterReading(.Id) is of Meter", u);
		fact(M, @"MeterReading has Quantity", u);
		fact(M, @"MeterReading has delta- Quantity", u);
		fact(M, @"MeterReading was taken at Moment", u);
		fact(M, @"MeterReading was recorded at Moment", u);
		fact(M, @"MeterReading has Comments()", u);
		fact(M, @"MeterReading has Photo()", u);

		/* Values, from the column types. */
		check([E.objectTypeEditor setValueConstraint:@"{'asc', 'desc', 'bidi'}" of:[[E.model objectTypeNamed:@"Direction"] identifier]
		                     reason:&reason], @"Direction values", reason);
		NSDictionary *texts = @{ @"SiteName": @50, @"EmailAddress": @200, @"FullName": @200, @"LocationName": @50,
		                         @"MeterGroupName": @100, @"ManufacturerName": @100, @"ModelName": @100,
		                         @"EquipmentTypeName": @100, @"SerialNumber": @100, @"EquipmentUnitName": @100,
		                         @"RecurrencePattern": @500, @"MimeType": @100, @"WorkOrderStatus": @50,
		                         @"Notes": @500, @"ScheduleInfo": @500, @"MeterTypeName": @100,
		                         @"UnitOfMeasure": @50, @"Direction": @5, @"MeterName": @100, @"MeterNumber": @100,
		                         @"Description": @200, @"Comments": @200 };
		for (NSString *name in texts) {
			dataType(name, @"VariableLengthTextDataType", [texts[name] integerValue], 0);
		}
		dataType(@"Date", @"DateTemporalDataType", 0, 0);
		dataType(@"Moment", @"DateAndTimeTemporalDataType", 0, 0);
		dataType(@"Money", @"DecimalNumericDataType", 18, 2);
		dataType(@"Quantity", @"DecimalNumericDataType", 18, 2);
		dataType(@"Instructions", @"LargeLengthRawDataDataType", 0, 0);
		dataType(@"Photo", @"FixedLengthRawDataDataType", 50, 0);
		/* Ids are identities, but WorkOrder's, which is given. */
		for (ORMObjectType *t in [E.model visibleObjectTypes]) {
			if (t.referenceModeValueType != nil) {
				dataType(t.referenceModeValueType.name, [t.name isEqualToString:@"WorkOrder"]
				                                            ? @"SignedLargeIntegerNumericDataType"
				                                            : @"AutoCounterNumericDataType", 0, 0);
			}
		}

		for (ORMDiagram *d in E.model.diagrams) {
			[E.diagramEditor arrangeDiagram:d.identifier];
		}
		[[E dataForSaving] writeToFile:@(argv[1]) atomically:YES];
		printf("%lu object types, %lu fact types, %lu constraints; %d failures\n",
		       (unsigned long)[[E.model visibleObjectTypes] count], (unsigned long)[[E.model ordinaryFactTypes] count],
		       (unsigned long)[E.model.constraints count], failures);
	}
	return failures != 0;
}
