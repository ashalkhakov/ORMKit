/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMInspectorView.h"
#import "ORMPath.h"

typedef NS_ENUM(NSInteger, ORMRowKind) {
	ORMRowHeader,
	ORMRowLabel,
	ORMRowText,
	ORMRowCheck,
	ORMRowPopup,
};

/* One property: where its value comes from, and how a new one is set. */
@interface ORMInspectorRow : NSObject
@property (nonatomic) ORMRowKind kind;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray<NSString *> *options;
/* NSString for text and labels, NSNumber for checks and popups. */
@property (nonatomic, copy) id (^value)(void);
@property (nonatomic, copy) BOOL (^set)(id value, NSString **reason);
@property (nonatomic, strong) NSControl *control;
@end

@implementation ORMInspectorRow
@end

static const double ORMLabelWidth = 92;
static const double ORMRowHeight = 24;

static ORMInspectorRow *
ORMRow(ORMRowKind kind, NSString *title, id (^value)(void), BOOL (^set)(id, NSString **))
{
	ORMInspectorRow *row = [[ORMInspectorRow alloc] init];
	row.kind = kind;
	row.title = title;
	row.value = value;
	row.set = set;
	return row;
}

@implementation ORMInspectorView
{
	NSMutableArray<ORMInspectorRow *> *_rows;
	NSMutableArray<NSView *> *_views;
	/* What the rows were built for: an element and its kind of row set. */
	NSString *_builtFor;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		_rows = [NSMutableArray array];
		_views = [NSMutableArray array];
	}
	return self;
}

/* From the document window's XIB, which does not call -initWithFrame:. */
- (void)awakeFromNib
{
	[super awakeFromNib];
	_rows = [NSMutableArray array];
	_views = [NSMutableArray array];
}

- (BOOL)isFlipped
{
	return YES;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

/* As wide as the clip view shows, whatever the column's width and however
 * wide the scroller: a clip view does not resize its document view. */
- (void)viewDidMoveToSuperview
{
	[super viewDidMoveToSuperview];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewFrameDidChangeNotification object:nil];
	NSView *superview = [self superview];
	if (superview == nil) {
		return;
	}
	[superview setPostsFrameChangedNotifications:YES];
	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(superviewFrameDidChange:)
	                                             name:NSViewFrameDidChangeNotification
	                                           object:superview];
	[self fitWidth];
}

- (void)superviewFrameDidChange:(NSNotification *)notification
{
	(void)notification;
	[self fitWidth];
}

- (void)fitWidth
{
	NSView *superview = [self superview];
	if (superview == nil) {
		return;
	}
	NSSize size = [self frame].size;
	size.width = NSWidth([superview bounds]);
	size.height = MAX(size.height, NSHeight([superview bounds]));
	if (!NSEqualSizes(size, [self frame].size)) {
		[self setFrameSize:size];
	}
}

- (void)setElementId:(NSString *)elementId
{
	_elementId = [elementId copy];
	[self rebuild];
}

- (void)setDiagramId:(NSString *)diagramId
{
	_diagramId = [diagramId copy];
	if (_elementId == nil) {
		[self rebuild];
	}
}

- (void)modelDidChange
{
	/* What it showed may be gone, or have become something else. */
	NSString *signature = [self signature];
	if (![signature isEqualToString:_builtFor]) {
		[self rebuild];
	} else {
		[self refill];
	}
}

/* What decides the rows: the element, and enough of what it is that a
 * change of kind (value type to entity type, a reading added) rebuilds. */
- (NSString *)signature
{
	id element = [self.editor.model elementWithId:self.elementId ?: self.diagramId];
	NSMutableString *signature = [NSMutableString stringWithFormat:@"%@:%@", [element identifier] ?: @"",
	                                                               NSStringFromClass([element class])];
	if ([element isKindOfClass:[ORMObjectType class]]) {
		ORMObjectType *type = element;
		[signature appendFormat:@":%ld:%d:%d", (long)type.kind, type.referenceMode != nil,
		                        type.nestedFactType != nil];
	} else if ([element isKindOfClass:[ORMFactType class]] || [element isKindOfClass:[ORMRole class]]) {
		ORMFactType *fact = [element isKindOfClass:[ORMRole class]] ? [(ORMRole *)element factType] : element;
		for (ORMReadingOrder *order in fact.readingOrders) {
			[signature appendFormat:@":%@:%lu", order.identifier, (unsigned long)[order.readings count]];
		}
		[signature appendFormat:@":%d", fact.objectifyingType != nil];
	} else if ([element isKindOfClass:[ORMConstraint class]]) {
		[signature appendFormat:@":%ld", (long)[(ORMConstraint *)element kind]];
	}
	return signature;
}

#pragma mark Rows

- (NSMutableArray *)rowsForObjectType:(ORMObjectType *)type
{
	ORMEditor *editor = self.editor;
	NSString *identifier = type.identifier;
	NSMutableArray *rows = [NSMutableArray array];
	[rows addObject:ORMRow(ORMRowHeader, type.kind == ORMValueType ? @"Value Type" : @"Entity Type", nil, nil)];
	[rows addObject:ORMRow(ORMRowText, @"Name", ^id {
		return [[editor.model elementWithId:identifier] name];
	}, ^BOOL(id value, NSString **reason) {
		return [editor.elementEditor rename:identifier to:value reason:reason];
	})];
	if (type.kind != ORMObjectifiedType) {
		ORMInspectorRow *kind = ORMRow(ORMRowPopup, @"Kind", ^id {
			return @([(ORMObjectType *)[editor.model elementWithId:identifier] kind] == ORMValueType ? 1 : 0);
		}, ^BOOL(id value, NSString **reason) {
			return [editor.objectTypeEditor setValueType:[value integerValue] == 1 of:identifier reason:reason];
		});
		kind.options = @[ @"Entity Type", @"Value Type" ];
		[rows addObject:kind];
	}
	if (type.isEntity && type.nestedFactType == nil) {
		[rows addObject:ORMRow(ORMRowText, @"Reference", ^id {
			ORMObjectType *now = [editor.model elementWithId:identifier];
			if (now.referenceMode == nil) {
				return @"";
			}
			return now.referenceModeKind == ORMReferenceModePopular ? [@"." stringByAppendingString:now.referenceMode]
				: now.referenceModeKind == ORMReferenceModeUnitBased ? [now.referenceMode stringByAppendingString:@":"]
				                                                     : now.referenceMode;
		}, ^BOOL(id value, NSString **reason) {
			return [editor.objectTypeEditor setReferenceMode:value kind:ORMReferenceModeGeneral ofEntity:identifier reason:reason];
		})];
	}
	ORMObjectType *valueType = type.kind == ORMValueType ? type : type.referenceModeValueType;
	if (valueType != nil) {
		NSString *valueId = valueType.identifier;
		NSArray *typeNames = [ORMDataType allTypeNames];
		NSMutableArray *titles = [NSMutableArray array];
		for (NSString *name in typeNames) {
			[titles addObject:[ORMDataType displayNameOfTypeNamed:name]];
		}
		ORMInspectorRow *dataType = ORMRow(ORMRowPopup, @"Data Type", ^id {
			ORMObjectType *now = [editor.model elementWithId:valueId];
			NSUInteger index = [typeNames indexOfObject:now.dataType.typeName ?: @"UnspecifiedDataType"];
			return @(index == NSNotFound ? 0 : index);
		}, ^BOOL(id value, NSString **reason) {
			ORMObjectType *now = [editor.model elementWithId:valueId];
			return [editor.objectTypeEditor setDataType:[typeNames objectAtIndex:[value unsignedIntegerValue]] length:now.dataTypeLength
			                     scale:now.dataTypeScale of:valueId reason:reason];
		});
		dataType.options = titles;
		[rows addObject:dataType];
		[rows addObject:ORMRow(ORMRowText, @"Length", ^id {
			NSInteger length = [(ORMObjectType *)[editor.model elementWithId:valueId] dataTypeLength];
			return length > 0 ? [NSString stringWithFormat:@"%ld", (long)length] : @"";
		}, ^BOOL(id value, NSString **reason) {
			ORMObjectType *now = [editor.model elementWithId:valueId];
			return [editor.objectTypeEditor setDataType:now.dataType.typeName ?: @"UnspecifiedDataType" length:[value integerValue]
			                     scale:now.dataTypeScale of:valueId reason:reason];
		})];
		[rows addObject:ORMRow(ORMRowText, @"Scale", ^id {
			NSInteger scale = [(ORMObjectType *)[editor.model elementWithId:valueId] dataTypeScale];
			return scale > 0 ? [NSString stringWithFormat:@"%ld", (long)scale] : @"";
		}, ^BOOL(id value, NSString **reason) {
			ORMObjectType *now = [editor.model elementWithId:valueId];
			return [editor.objectTypeEditor setDataType:now.dataType.typeName ?: @"UnspecifiedDataType" length:now.dataTypeLength
			                     scale:[value integerValue] of:valueId reason:reason];
		})];
		[rows addObject:ORMRow(ORMRowText, @"Values", ^id {
			ORMValueConstraint *constraint = [(ORMObjectType *)[editor.model elementWithId:valueId] valueConstraint];
			return constraint != nil ? [constraint displayText] : @"";
		}, ^BOOL(id value, NSString **reason) {
			return [editor.objectTypeEditor setValueConstraint:value of:valueId reason:reason];
		})];
	}
	[rows addObject:ORMRow(ORMRowCheck, @"Independent", ^id {
		return @([(ORMObjectType *)[editor.model elementWithId:identifier] isIndependent]);
	}, ^BOOL(id value, NSString **reason) {
		return [editor.objectTypeEditor setIndependent:[value boolValue] of:identifier reason:reason];
	})];
	[rows addObject:ORMRow(ORMRowCheck, @"Personal", ^id {
		return @([(ORMObjectType *)[editor.model elementWithId:identifier] isPersonal]);
	}, ^BOOL(id value, NSString **reason) {
		return [editor.objectTypeEditor setPersonal:[value boolValue] of:identifier reason:reason];
	})];
	[rows addObject:ORMRow(ORMRowCheck, @"External", ^id {
		return @([(ORMObjectType *)[editor.model elementWithId:identifier] isExternal]);
	}, ^BOOL(id value, NSString **reason) {
		return [editor.objectTypeEditor setExternal:[value boolValue] of:identifier reason:reason];
	})];
	[rows addObjectsFromArray:[self textRowsFor:identifier]];
	return rows;
}

/* NORMA's Definitions/Definition/Text, or Notes/Note/Text, of an object
 * type or fact type. */
static NSString *
ORMNestedTextOf(ORMElement *element, NSString *container, NSString *item)
{
	NSXMLElement *first = [ORMGrandchildren(element.element, ORMCoreNamespace, container, ORMCoreNamespace, item)
		firstObject];
	return ORMChildText(first, ORMCoreNamespace, @"Text") ?: @"";
}

- (NSArray *)textRowsFor:(NSString *)identifier
{
	ORMEditor *editor = self.editor;
	return @[
		ORMRow(ORMRowText, @"Definition", ^id {
			return ORMNestedTextOf([editor.model elementWithId:identifier], @"Definitions", @"Definition");
		}, ^BOOL(id value, NSString **reason) {
			return [editor.elementEditor setDefinition:value of:identifier reason:reason];
		}),
		ORMRow(ORMRowText, @"Note", ^id {
			return ORMNestedTextOf([editor.model elementWithId:identifier], @"Notes", @"Note");
		}, ^BOOL(id value, NSString **reason) {
			return [editor.elementEditor setNote:value of:identifier reason:reason];
		}),
	];
}

/* A reading edited as a sentence with the players' names: "Person was
 * born in Country", turned back into "{0} was born in {1}". */
- (ORMInspectorRow *)readingRow:(ORMReading *)reading title:(NSString *)title
{
	ORMEditor *editor = self.editor;
	NSString *readingId = reading.identifier;
	return ORMRow(ORMRowText, title, ^id {
		return [[editor.model elementWithId:readingId] expandedText] ?: @"";
	}, ^BOOL(id value, NSString **reason) {
		ORMReading *now = [editor.model elementWithId:readingId];
		NSMutableArray *names = [NSMutableArray array];
		for (ORMRole *role in now.readingOrder.roles) {
			[names addObject:role.player.name ?: @""];
		}
		NSString *text = [value length] == 0 ? @""
			: ([value rangeOfString:@"{0}"].location != NSNotFound
			       ? value
			       : [ORMReadingText readingFromSentence:value withNames:names reason:reason]);
		if (text == nil) {
			return NO;
		}
		return [editor.factTypeEditor setReadingText:text of:readingId reason:reason];
	});
}

- (NSMutableArray *)rowsForFactType:(ORMFactType *)fact
{
	ORMEditor *editor = self.editor;
	NSString *identifier = fact.identifier;
	NSMutableArray *rows = [NSMutableArray array];
	[rows addObject:ORMRow(ORMRowHeader, @"Fact Type", nil, nil)];
	NSUInteger number = 0;
	for (ORMReadingOrder *order in fact.readingOrders) {
		for (ORMReading *reading in order.readings) {
			number++;
			[rows addObject:[self readingRow:reading title:number == 1 ? @"Reading" : @"Reading"]];
		}
	}
	NSArray *roles = [fact visibleRoles];
	if ([roles count] == 2 && [fact readingOrderForRoles:[[roles reverseObjectEnumerator] allObjects]] == nil) {
		NSArray *reversed = @[ [roles objectAtIndex:1], [roles objectAtIndex:0] ];
		[rows addObject:ORMRow(ORMRowText, @"Reverse", ^id {
			return @"";
		}, ^BOOL(id value, NSString **reason) {
			if ([value length] == 0) {
				return YES;
			}
			NSArray *names = @[ [[reversed objectAtIndex:0] player].name ?: @"", [[reversed objectAtIndex:1] player].name ?: @"" ];
			NSString *text = [value rangeOfString:@"{0}"].location != NSNotFound
				? value : [ORMReadingText readingFromSentence:value withNames:names reason:reason];
			if (text == nil) {
				return NO;
			}
			return [editor.factTypeEditor addReading:text forRoles:@[ [[reversed objectAtIndex:0] identifier],
			                                           [[reversed objectAtIndex:1] identifier] ] reason:reason] != nil;
		})];
	}
	[rows addObject:ORMRow(ORMRowLabel, @"Name", ^id {
		return [[editor.model elementWithId:identifier] derivedName] ?: @"";
	}, nil)];
	[rows addObject:ORMRow(ORMRowCheck, @"Objectified", ^id {
		return @([(ORMFactType *)[editor.model elementWithId:identifier] objectifyingType] != nil);
	}, ^BOOL(id value, NSString **reason) {
		if ([value boolValue]) {
			return [editor.factTypeEditor objectifyFactType:identifier named:nil reason:reason] != nil;
		}
		return [editor.factTypeEditor unobjectifyFactType:identifier reason:reason];
	})];
	if (fact.objectifyingType != nil) {
		[rows addObject:ORMRow(ORMRowText, @"As", ^id {
			return [[(ORMFactType *)[editor.model elementWithId:identifier] objectifyingType] name] ?: @"";
		}, ^BOOL(id value, NSString **reason) {
			ORMObjectType *type = [(ORMFactType *)[editor.model elementWithId:identifier] objectifyingType];
			return [editor.elementEditor rename:type.identifier to:value reason:reason];
		})];
	}
	/* Derived (docs/DERIVATION.md): by what, and how; a query's words are
	 * its own, kept by the normalizer. */
	ORMQuery *derivation = fact.isDerived ? [ORMQuery derivationOf:fact inModel:editor.model] : nil;
	if (fact.isDerived) {
		[rows addObject:ORMRow(ORMRowLabel, @"Derived by", ^id {
			ORMFactType *now = [editor.model elementWithId:identifier];
			ORMQuery *query = [ORMQuery derivationOf:now inModel:editor.model];
			if (query != nil) {
				return [NSString stringWithFormat:@"the query %@", query.name];
			}
			return [[now derivationRule].paths count] > 0 ? @"NORMA's rule" : @"its note";
		}, nil)];
		[rows addObject:ORMRow(ORMRowCheck, @"Partly Derived", ^id {
			return @([[(ORMFactType *)[editor.model elementWithId:identifier] derivationRule] isPartial]);
		}, ^BOOL(id value, NSString **reason) {
			ORMDerivationRule *rule = [(ORMFactType *)[editor.model elementWithId:identifier] derivationRule];
			return [editor.factTypeEditor setDerivationPartial:[value boolValue] stored:rule.isStored of:identifier
			                                            reason:reason];
		})];
		[rows addObject:ORMRow(ORMRowCheck, @"Stored", ^id {
			return @([[(ORMFactType *)[editor.model elementWithId:identifier] derivationRule] isStored]);
		}, ^BOOL(id value, NSString **reason) {
			ORMDerivationRule *rule = [(ORMFactType *)[editor.model elementWithId:identifier] derivationRule];
			return [editor.factTypeEditor setDerivationPartial:rule.isPartial stored:[value boolValue] of:identifier
			                                            reason:reason];
		})];
	}
	if (derivation != nil) {
		[rows addObject:ORMRow(ORMRowLabel, @"Derivation", ^id {
			return [[(ORMFactType *)[editor.model elementWithId:identifier] derivationRule] informalText] ?: @"";
		}, nil)];
	} else {
		[rows addObject:ORMRow(ORMRowText, @"Derivation", ^id {
			return [[(ORMFactType *)[editor.model elementWithId:identifier] derivationRule] informalText] ?: @"";
		}, ^BOOL(id value, NSString **reason) {
			return [editor.factTypeEditor setDerivationNote:value of:identifier reason:reason];
		})];
	}
	[rows addObjectsFromArray:[self textRowsFor:identifier]];
	return rows;
}

- (NSMutableArray *)rowsForRole:(ORMRole *)role
{
	ORMEditor *editor = self.editor;
	NSString *identifier = role.identifier;
	NSMutableArray *rows = [NSMutableArray array];
	[rows addObject:ORMRow(ORMRowHeader, @"Role", nil, nil)];
	[rows addObject:ORMRow(ORMRowLabel, @"Player", ^id {
		return [[[editor.model elementWithId:identifier] player] name] ?: @"(none)";
	}, nil)];
	[rows addObject:ORMRow(ORMRowText, @"Role Name", ^id {
		return [[editor.model elementWithId:identifier] name] ?: @"";
	}, ^BOOL(id value, NSString **reason) {
		return [editor.elementEditor rename:identifier to:value reason:reason];
	})];
	[rows addObject:ORMRow(ORMRowCheck, @"Mandatory", ^id {
		return @([(ORMRole *)[editor.model elementWithId:identifier] isMandatory]);
	}, ^BOOL(id value, NSString **reason) {
		return [editor.constraintEditor setMandatory:[value boolValue] role:identifier reason:reason];
	})];
	[rows addObject:ORMRow(ORMRowCheck, @"Unique", ^id {
		return @([(ORMRole *)[editor.model elementWithId:identifier] isUnique]);
	}, ^BOOL(id value, NSString **reason) {
		return [editor.constraintEditor setUnique:[value boolValue] role:identifier reason:reason];
	})];
	[rows addObject:ORMRow(ORMRowText, @"Values", ^id {
		ORMValueConstraint *constraint = [(ORMRole *)[editor.model elementWithId:identifier] valueConstraint];
		return constraint != nil ? [constraint displayText] : @"";
	}, ^BOOL(id value, NSString **reason) {
		return [editor.objectTypeEditor setValueConstraint:value of:identifier reason:reason];
	})];
	[rows addObjectsFromArray:[self rowsForFactType:role.factType]];
	return rows;
}

- (NSMutableArray *)rowsForConstraint:(ORMConstraint *)constraint
{
	ORMEditor *editor = self.editor;
	NSString *identifier = constraint.identifier;
	NSDictionary *titles = @{ @(ORMUniquenessConstraint): @"Uniqueness Constraint",
	                          @(ORMMandatoryConstraint): constraint.isSimple ? @"Mandatory Constraint"
	                                                                         : @"Inclusive-Or Constraint",
	                          @(ORMFrequencyConstraint): @"Frequency Constraint",
	                          @(ORMRingConstraint): @"Ring Constraint",
	                          @(ORMSubsetConstraint): @"Subset Constraint",
	                          @(ORMEqualityConstraint): @"Equality Constraint",
	                          @(ORMExclusionConstraint): constraint.exclusiveOrPartner != nil ? @"Exclusive-Or Constraint"
	                                                                                          : @"Exclusion Constraint",
	                          @(ORMValueComparisonConstraint): @"Value Comparison" };
	NSMutableArray *rows = [NSMutableArray array];
	[rows addObject:ORMRow(ORMRowHeader, [titles objectForKey:@(constraint.kind)], nil, nil)];
	[rows addObject:ORMRow(ORMRowText, @"Name", ^id {
		return [[editor.model elementWithId:identifier] name] ?: @"";
	}, ^BOOL(id value, NSString **reason) {
		return [editor.elementEditor rename:identifier to:value reason:reason];
	})];
	ORMInspectorRow *modality = ORMRow(ORMRowPopup, @"Modality", ^id {
		return @([(ORMConstraint *)[editor.model elementWithId:identifier] modality] == ORMDeontic ? 1 : 0);
	}, ^BOOL(id value, NSString **reason) {
		return [editor.constraintEditor setModality:[value integerValue] == 1 ? ORMDeontic : ORMAlethic of:identifier reason:reason];
	});
	modality.options = @[ @"Alethic (necessary)", @"Deontic (obligatory)" ];
	[rows addObject:modality];
	switch (constraint.kind) {
	case ORMUniquenessConstraint: {
		[rows addObject:ORMRow(ORMRowCheck, @"Identifies", ^id {
			return @([(ORMConstraint *)[editor.model elementWithId:identifier] preferredIdentifierFor] != nil);
		}, ^BOOL(id value, NSString **reason) {
			if (![value boolValue]) {
				if (reason != NULL) {
					*reason = @"Give the entity type another identifier instead.";
				}
				return NO;
			}
			return [editor.constraintEditor setPreferredIdentifier:identifier reason:reason];
		})];
		break;
	}
	case ORMFrequencyConstraint: {
		[rows addObject:ORMRow(ORMRowText, @"At Least", ^id {
			return [NSString stringWithFormat:@"%lu", (unsigned long)[(ORMConstraint *)[editor.model elementWithId:identifier]
			                                                             minFrequency]];
		}, ^BOOL(id value, NSString **reason) {
			ORMConstraint *now = [editor.model elementWithId:identifier];
			return [editor.constraintEditor setFrequencyMin:(NSUInteger)MAX(0, [value integerValue]) max:now.maxFrequency of:identifier
			                        reason:reason];
		})];
		[rows addObject:ORMRow(ORMRowText, @"At Most", ^id {
			NSUInteger max = [(ORMConstraint *)[editor.model elementWithId:identifier] maxFrequency];
			return max > 0 ? [NSString stringWithFormat:@"%lu", (unsigned long)max] : @"";
		}, ^BOOL(id value, NSString **reason) {
			ORMConstraint *now = [editor.model elementWithId:identifier];
			return [editor.constraintEditor setFrequencyMin:now.minFrequency max:(NSUInteger)MAX(0, [value integerValue]) of:identifier
			                        reason:reason];
		})];
		break;
	}
	case ORMRingConstraint: {
		NSArray *properties = @[ @[ @"Reflexive", @(ORMRingReflexive) ], @[ @"Irreflexive", @(ORMRingIrreflexive) ],
		                         @[ @"Symmetric", @(ORMRingSymmetric) ], @[ @"Asymmetric", @(ORMRingAsymmetric) ],
		                         @[ @"Antisymmetric", @(ORMRingAntisymmetric) ],
		                         @[ @"Transitive", @(ORMRingTransitive) ], @[ @"Intransitive", @(ORMRingIntransitive) ],
		                         @[ @"Strongly Intrans.", @(ORMRingStronglyIntransitive) ],
		                         @[ @"Acyclic", @(ORMRingAcyclic) ], @[ @"Purely Reflexive", @(ORMRingPurelyReflexive) ] ];
		for (NSArray *property in properties) {
			ORMRingType bit = [[property objectAtIndex:1] unsignedIntegerValue];
			[rows addObject:ORMRow(ORMRowCheck, [property objectAtIndex:0], ^id {
				return @(([(ORMConstraint *)[editor.model elementWithId:identifier] ringType] & bit) != 0);
			}, ^BOOL(id value, NSString **reason) {
				ORMRingType type = [(ORMConstraint *)[editor.model elementWithId:identifier] ringType];
				type = [value boolValue] ? (type | bit) : (type & ~bit);
				return [editor.constraintEditor setRingType:type of:identifier reason:reason];
			})];
		}
		break;
	}
	default:
		break;
	}
	return rows;
}

- (NSMutableArray *)rowsForNote:(ORMModelNote *)note
{
	ORMEditor *editor = self.editor;
	NSString *identifier = note.identifier;
	NSMutableArray *rows = [NSMutableArray array];
	[rows addObject:ORMRow(ORMRowHeader, @"Note", nil, nil)];
	[rows addObject:ORMRow(ORMRowText, @"Text", ^id {
		return [(ORMModelNote *)[editor.model elementWithId:identifier] text] ?: @"";
	}, ^BOOL(id value, NSString **reason) {
		return [editor.elementEditor setNoteText:value of:identifier reason:reason];
	})];
	return rows;
}

- (NSMutableArray *)rowsForDiagram:(ORMDiagram *)diagram
{
	ORMEditor *editor = self.editor;
	NSString *identifier = diagram.identifier;
	NSMutableArray *rows = [NSMutableArray array];
	[rows addObject:ORMRow(ORMRowHeader, @"Diagram", nil, nil)];
	[rows addObject:ORMRow(ORMRowText, @"Name", ^id {
		return [[editor.model elementWithId:identifier] name] ?: @"";
	}, ^BOOL(id value, NSString **reason) {
		return [editor.elementEditor rename:identifier to:value reason:reason];
	})];
	[rows addObject:ORMRow(ORMRowLabel, @"Model", ^id {
		return editor.model.name ?: @"";
	}, nil)];
	[rows addObject:ORMRow(ORMRowLabel, @"Contents", ^id {
		ORMModel *model = editor.model;
		return [NSString stringWithFormat:@"%lu object types, %lu fact types",
		        (unsigned long)[[model visibleObjectTypes] count], (unsigned long)[[model ordinaryFactTypes] count]];
	}, nil)];
	return rows;
}

#pragma mark Building

- (void)rebuild
{
	for (NSView *view in _views) {
		[view removeFromSuperview];
	}
	[_views removeAllObjects];
	[_rows removeAllObjects];
	id element = [self.editor.model elementWithId:self.elementId];
	if ([element isKindOfClass:[ORMObjectType class]]) {
		[_rows addObjectsFromArray:[self rowsForObjectType:element]];
	} else if ([element isKindOfClass:[ORMRole class]]) {
		[_rows addObjectsFromArray:[self rowsForRole:element]];
	} else if ([element isKindOfClass:[ORMFactType class]]) {
		[_rows addObjectsFromArray:[self rowsForFactType:element]];
	} else if ([element isKindOfClass:[ORMConstraint class]]) {
		[_rows addObjectsFromArray:[self rowsForConstraint:element]];
	} else if ([element isKindOfClass:[ORMModelNote class]]) {
		[_rows addObjectsFromArray:[self rowsForNote:element]];
	} else {
		ORMDiagram *diagram = [self.editor.model elementWithId:self.diagramId];
		if ([diagram isKindOfClass:[ORMDiagram class]]) {
			[_rows addObjectsFromArray:[self rowsForDiagram:diagram]];
		}
	}
	_builtFor = [self signature];
	[self layoutRows];
	[self refill];
}

- (void)layoutRows
{
	double width = NSWidth([self bounds]);
	double y = 6;
	NSFont *font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
	for (ORMInspectorRow *row in _rows) {
		if (row.kind == ORMRowHeader) {
			y += 4;
			NSTextField *header = [self labelWithText:row.title font:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
			[header setFrame:NSMakeRect(8, y, width - 16, 18)];
			[header setAutoresizingMask:NSViewWidthSizable];
			[self addSubview:header];
			[_views addObject:header];
			y += 22;
			continue;
		}
		if (row.kind != ORMRowCheck) {
			NSTextField *label = [self labelWithText:row.title font:font];
			[label setAlignment:NSTextAlignmentRight];
			[label setFrame:NSMakeRect(4, y + 3, ORMLabelWidth - 8, 16)];
			[self addSubview:label];
			[_views addObject:label];
		}
		NSRect frame = NSMakeRect(ORMLabelWidth, y, width - ORMLabelWidth - 8, 20);
		NSControl *control = nil;
		switch (row.kind) {
		case ORMRowLabel: {
			NSTextField *field = [self labelWithText:@"" font:font];
			[field setSelectable:YES];
			frame.origin.y += 3;
			frame.size.height = 16;
			[field setFrame:frame];
			control = field;
			break;
		}
		case ORMRowText: {
			NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
			[field setFont:font];
			[[field cell] setSendsActionOnEndEditing:YES];
			[[field cell] setScrollable:YES];
			control = field;
			break;
		}
		case ORMRowCheck: {
			NSButton *check = [[NSButton alloc] initWithFrame:frame];
			[check setButtonType:NSButtonTypeSwitch];
			[check setTitle:row.title];
			[check setFont:font];
			control = check;
			break;
		}
		case ORMRowPopup: {
			NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(NSMinX(frame), NSMinY(frame) - 1,
			                                                                      NSWidth(frame), 22)
			                                                  pullsDown:NO];
			[popup setFont:font];
			[popup addItemsWithTitles:row.options];
			control = popup;
			break;
		}
		case ORMRowHeader:
			break;
		}
		[control setAutoresizingMask:NSViewWidthSizable];
		if (row.set != nil) {
			[control setTarget:self];
			[control setAction:@selector(rowChanged:)];
		} else if ([control isKindOfClass:[NSTextField class]]) {
			[(NSTextField *)control setEditable:NO];
		}
		row.control = control;
		[self addSubview:control];
		[_views addObject:control];
		y += ORMRowHeight;
	}
	NSRect frame = [self frame];
	frame.size.height = MAX(y + 8, NSHeight([[self superview] bounds]));
	[self setFrame:frame];
}

- (NSTextField *)labelWithText:(NSString *)text font:(NSFont *)font
{
	NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[label setStringValue:text ?: @""];
	[label setFont:font];
	[label setEditable:NO];
	[label setBordered:NO];
	[label setDrawsBackground:NO];
	[label setBezeled:NO];
	return label;
}

/* Puts the model's values into the controls, leaving alone the one being
 * typed in. */
- (void)refill
{
	NSResponder *first = [[self window] firstResponder];
	for (ORMInspectorRow *row in _rows) {
		NSControl *control = row.control;
		if (control == nil || row.value == nil) {
			continue;
		}
		BOOL editing = [first isKindOfClass:[NSText class]] && [(NSText *)first delegate] == (id)control;
		if (editing) {
			continue;
		}
		id value = row.value();
		switch (row.kind) {
		case ORMRowText:
		case ORMRowLabel:
			[(NSTextField *)control setStringValue:value ?: @""];
			break;
		case ORMRowCheck:
			[(NSButton *)control setState:[value boolValue] ? NSControlStateValueOn : NSControlStateValueOff];
			break;
		case ORMRowPopup:
			[(NSPopUpButton *)control selectItemAtIndex:[value integerValue]];
			break;
		case ORMRowHeader:
			break;
		}
	}
}

- (void)rowChanged:(id)sender
{
	for (ORMInspectorRow *row in _rows) {
		if (row.control != sender || row.set == nil) {
			continue;
		}
		id value = nil;
		switch (row.kind) {
		case ORMRowText:
			value = [(NSTextField *)sender stringValue];
			if ([value isEqualToString:row.value() ?: @""]) {
				return;
			}
			break;
		case ORMRowCheck:
			value = @([(NSButton *)sender state] == NSControlStateValueOn);
			break;
		case ORMRowPopup:
			value = @([(NSPopUpButton *)sender indexOfSelectedItem]);
			if ([value isEqual:row.value()]) {
				return;
			}
			break;
		default:
			return;
		}
		NSString *reason = nil;
		if (!row.set(value, &reason)) {
			NSBeep();
			[self.delegate inspector:self say:reason ?: @"That cannot be done."];
			[self refill];
		}
		return;
	}
}

@end
