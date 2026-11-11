/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMFormDocument.h"

/* A customized copy of a form's XForms document, kept with the app's
 * sources and edited freely (docs/FORMS.md, Customizing), checked against
 * the form as a contract: what it is given, what is entered and shown, what
 * a save writes.
 *
 *   - errors: an input it does not take (a given element its instance
 *     lacks), an element the contract has not, unmarked, or one the
 *     contract enters that no control of it binds;
 *   - warnings: a looser bind (one the model's requires or constrains, the
 *     copy's not): refused where it is submitted, not as it is filled in;
 *   - provisional elements: what it adds that the model has no fact type
 *     for, marked so (ormf:provisional="true" on the instance's element),
 *     the form under construction while it has one. Each is a question for
 *     the modeller, and what -proposalGiven: proposes.
 */
@interface ORMFormCustomization : NSObject
+ (instancetype)customization:(NSXMLDocument *)copy ofForm:(ORMFormDocument *)form;
@property (nonatomic, readonly, strong) ORMFormDocument *form;
@property (nonatomic, readonly, copy) NSArray<NSString *> *errors;
@property (nonatomic, readonly, copy) NSArray<NSString *> *warnings;
@property (nonatomic, readonly, copy) NSArray<NSString *> *provisionalElements;
- (BOOL)isUnderConstruction;
/* The fact types the provisional elements ask for, as FORML the sentence
 * editor reads (ormtool apply): each a value type, typed by its bind or,
 * where it has none, by the values a sample filled in has (an instance of
 * the copy's, or nil); the fact type of its object's (the anchor's, an
 * owned one's) with it, one of it each, exactly one where the copy
 * requires it, its values where the copy lists them; a flag (boolean) a
 * unary. After each, the step the form is to have, as a comment. */
- (NSString *)proposalGiven:(NSXMLDocument *)sample;
@end
