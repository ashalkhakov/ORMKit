/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQuery.h"

@class ORMCoreDataMapping;

/* What each node of a form is (docs/FORMS.md, The definition): its place,
 * decided from the steps above it before its mark, and the one rule it is
 * translated by (D1-D16), or the one it breaks (E1-E7), which makes the
 * outline no form: refused where it is drawn, never generated.
 *
 *   Form RecordFillUp:
 *   FillUp                          D1   the anchor
 *     + is of Vehicle1 = ?          D2   given
 *       + has Plate (shown)         D7   shown, read through the reference
 *     + was at Moment (entered)     D3   entered on the anchor
 *     + had driver User (entered)   D4   a choice
 *       + drives Vehicle1           D5   a condition on it
 *     + filled the tank (entered)   D10  a flag
 *     + has Colour (entered)        E1   under "+ is of Vehicle (entered)":
 *                                        not a key of it
 */

/* Where a node is. */
typedef NS_ENUM(NSInteger, ORMFormPlace) {
	/* The outline's root: the object made or changed. */
	ORMFormPlaceAnchor,
	/* An entity reached from the anchor or an owned object, unmarked, with
	 * something entered beneath: made and changed with the anchor. */
	ORMFormPlaceOwned,
	/* Any other entity: chosen, given, shown, or passed through. */
	ORMFormPlaceReferenced,
	/* Reached by a subtype step: the object above, of that subtype. */
	ORMFormPlacePart,
	/* A value object the mapping keeps in its owner's row (Money, Volume). */
	ORMFormPlaceAbsorbed,
	/* A value: an attribute of its owner. */
	ORMFormPlaceValue,
	/* A value node, computed. */
	ORMFormPlaceComputed,
};

/* A rule an outline breaks, at a node or a unary step. */
@interface ORMFormProblem : NSObject
/* "E1" ... "E7". */
@property (nonatomic, readonly, copy) NSString *rule;
/* The node's id, or the unary step's. */
@property (nonatomic, readonly, copy) NSString *partId;
/* "E1: Colour: ...": the rule, the node, and why. */
@property (nonatomic, readonly, copy) NSString *text;
@end

@interface ORMFormDefinition : NSObject
/* The form's nodes, through the mapping (the defaults for nil). nil for a
 * query that is no form. */
+ (instancetype)definitionOfForm:(ORMQuery *)form model:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping;
@property (nonatomic, readonly, strong) ORMQuery *form;
- (ORMFormPlace)placeOfNode:(ORMQueryNode *)node;
/* A step is to one when the role it leaves from is unique, or it is a
 * subtype's; else to many. */
- (BOOL)isToMany:(ORMQueryStep *)step;
/* The rule a node or step is translated by ("D3"), or the one it breaks
 * ("E1"); "path" for an unmarked node on the way to what is marked; nil
 * for a step that is no repeat, list or flag. */
- (NSString *)ruleOf:(NSString *)partId;
/* The rules broken, in outline order: none for a well-formed form. */
@property (nonatomic, readonly, copy) NSArray<ORMFormProblem *> *problems;
/* Their nodes' and steps' ids. */
- (NSSet<NSString *> *)problemIds;

/* What the generator needs of each node beyond its rule: a choice it is
 * beneath (D5, D6, D7 through it), the nodes the choice's identification
 * is (D6), and whether a step is a repeat (D8) or a list (D9). */
- (ORMQueryNode *)choiceAbove:(ORMQueryNode *)node;
- (BOOL)identifiesChoice:(ORMQueryNode *)node;
- (BOOL)isRepeat:(ORMQueryStep *)step;
- (BOOL)isList:(ORMQueryStep *)step;
@end
