#import <Foundation/Foundation.h>

/* What ORMKit reads and writes of a NORMA .orm file, through NSXML.
 *
 * A NORMA file is an ormRoot:ORM2 element holding the model (orm:ORMModel),
 * its diagrams (ormDiagram:ORMDiagram) and whatever NORMA's extensions
 * saved beside them: the abstraction and relational bridges, name
 * generators, display state. ORMKit edits the document in place and leaves
 * what it does not know alone, so a file goes back to NORMA with all of it. */

extern NSString * const ORMRootNamespace;
extern NSString * const ORMCoreNamespace;
extern NSString * const ORMDiagramNamespace;
extern NSString * const ORMDiagramDisplayNamespace;
/* ORMKit's own: the Core Data mappings (ORMCoreDataBridge). */
extern NSString * const ORMCoreDataNamespace;
/* ORMKit's own: conceptual queries (ORMQuery). */
extern NSString * const ORMQueryNamespace;
/* ORMKit's own namespaces, which NORMA does not know. */
NSArray<NSString *> *ORMKitNamespaces(void);

/* NORMA's generated relational artefacts. They are a function of the model,
 * and NORMA rebuilds them when they are missing; ORMKit drops them from a
 * file it has changed (-[ORMEditor documentForSaving]) rather than leave
 * them describing a model that is gone. */
NSArray<NSString *> *ORMGeneratedNamespaces(void);

/* The node is the element of that namespace and local name; local nil:
 * any element of the namespace. */
BOOL ORMIs(NSXMLNode *node, NSString *uri, NSString *local);
NSArray<NSXMLElement *> *ORMChildren(NSXMLElement *element, NSString *uri, NSString *local);
NSXMLElement *ORMChild(NSXMLElement *element, NSString *uri, NSString *local);
/* The child of the child: ORMChildAt(fact, core, @"FactRoles", core, @"Role")
 * is a fact's roles. */
NSArray<NSXMLElement *> *ORMGrandchildren(NSXMLElement *element, NSString *uri, NSString *local,
                                          NSString *childURI, NSString *childLocal);
/* Every element below, in document order. */
NSArray<NSXMLElement *> *ORMDescendants(NSXMLElement *element, NSString *uri, NSString *local);

/* An unqualified attribute; nil when it has none. */
NSString *ORMAttribute(NSXMLElement *element, NSString *name);
/* Sets it, or with nil removes it. */
void ORMSetAttribute(NSXMLElement *element, NSString *name, NSString *value);
/* "true" is YES; anything else, or no attribute, is the default. */
BOOL ORMBoolAttribute(NSXMLElement *element, NSString *name, BOOL fallback);
/* Writes "true", or with the default removes the attribute: NORMA leaves
 * defaults out. */
void ORMSetBoolAttribute(NSXMLElement *element, NSString *name, BOOL value, BOOL fallback);
/* The ref attribute: what most of NORMA's elements point with. */
NSString *ORMRef(NSXMLElement *element);

/* A new element of the namespace, with the prefix the document gives it,
 * declared on the root under NORMA's usual one when the document has none. */
NSXMLElement *ORMNewElement(NSXMLDocument *document, NSString *uri, NSString *local);
/* A new element with an id. */
NSXMLElement *ORMNewElementWithId(NSXMLDocument *document, NSString *uri, NSString *local, NSString *elementId);
/* A new <prefix:local ref="target"/>. */
NSXMLElement *ORMNewRef(NSXMLDocument *document, NSString *uri, NSString *local, NSString *target);

/* The child, made where NORMA's schema puts it when there is none. */
NSXMLElement *ORMEnsureChild(NSXMLDocument *document, NSXMLElement *parent, NSString *uri, NSString *local);
/* Inserts the child where NORMA's schema puts it among its siblings. */
void ORMInsertChild(NSXMLElement *parent, NSXMLElement *child);
/* The child's text; nil when there is no such child. */
NSString *ORMChildText(NSXMLElement *parent, NSString *uri, NSString *local);
/* Sets the child's text, making the child; nil or empty removes it. */
NSXMLElement *ORMSetChildText(NSXMLDocument *document, NSXMLElement *parent, NSString *uri, NSString *local,
                              NSString *text);
/* Removes the child when it has no element children left: NORMA writes no
 * empty containers. */
void ORMPruneIfEmpty(NSXMLElement *element);

/* An id as NORMA makes them: an underscore and an upper-case GUID. */
NSString *ORMNewId(void);
/* Every element of the document with the id. */
NSXMLElement *ORMElementWithId(NSXMLDocument *document, NSString *elementId);
/* Every element with an id, by it. */
NSDictionary<NSString *, NSXMLElement *> *ORMIndexIds(NSXMLDocument *document);
/* A copy that writes as the original does -- Apple's copy drops the XML
 * declaration's standalone: what an editor's undo restores. */
NSXMLDocument *ORMCopyDocument(NSXMLDocument *document);

/* NORMA measures diagrams in inches; ORMKit draws in points. */
extern const double ORMPointsPerInch;
/* "x, y, width, height" in inches, as AbsoluteBounds holds it, in points. */
NSRect ORMParseBounds(NSString *text);
NSString *ORMFormatBounds(NSRect bounds);
/* "x, y" in inches, in points. */
NSPoint ORMParsePoint(NSString *text);
NSString *ORMFormatPoint(NSPoint point);

/* The serialized file: UTF-8 with a byte-order mark and tabs, as NORMA
 * writes it, so an unchanged file comes back byte for byte where NSXML
 * allows. */
NSData *ORMDataOfDocument(NSXMLDocument *document);
/* nil with why when the data is not XML. */
NSXMLDocument *ORMParseDocument(NSData *data, NSString **reason);
