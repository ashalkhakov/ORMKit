/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>
#if __has_include(<ORMKit/ORMKit.h>)
#import <ORMKit/ORMKit.h>
#else
#import "ORMKit.h"
#endif
#include <stdio.h>

/* ORMKit from the command line: what CI smoke-tests, and what scripts use.
 *
 *   ormtool verbalize [--html] model.orm     the model as FORML sentences
 *   ormtool check model.orm                  what the model holds, and whether it reads;
 *                                            its sample population against its
 *                                            constraints and constraint queries
 *                                            (1 when it breaks an alethic one)
 *   ormtool normalize model.orm [out.orm]    NORMA's derived data brought up to date
 *   ormtool coredata model.orm Out.xcdatamodeld [mapping name] [--validation dir/]
 *                                            the model mapped to Core Data, with the mapping's report;
 *                                            the validation code too, where the mapping keeps it or
 *                                            into dir/ (what a build generates, outside the sources)
 *   ormtool validation model.orm dir/ [mapping name]
 *                                            code checking what Core Data cannot enforce:
 *                                            <Name>Validation.h and .m, a category on each class
 *   ormtool svg [--dark] model.orm [out.svg | dir/] [diagram name]
 *                                            a diagram as SVG: the first (or the named) to standard
 *                                            output or the file; every one (or the named) into a
 *                                            directory, one file a diagram
 *   ormtool query model.orm [query name] [mapping name]
 *                                            the model's queries (or the named one): ConQuer's
 *                                            outline, the FORML, the OData request to the service
 *                                            ODataKit makes of the mapping, the plan, how the
 *                                            interpreter runs it against a Core Data store, and
 *                                            the rows it finds in the sample population
 *   ormtool import Model.xcdatamodeld [model.orm]
 *                                            the Core Data model in ORM: added to the .orm when it
 *                                            exists, else a new model, written there or to standard
 *                                            output, with what ORM cannot say on standard error
 *   ormtool forml model.orm [out.forml]      the model as schema text (ORMSchemaText.h): a listing,
 *                                            a statement a line, by diagram, with each element's
 *                                            note as a comment; what build and apply read
 *   ormtool apply model.orm changes.forml [out.orm]
 *                                            lines of schema text applied to the model, as one change:
 *                                            what they say made, what "- line" says taken away, a
 *                                            query of a name the model has replaced; the file written
 *                                            back (or out.orm) only when every line was read (1)
 *   ormtool sync model.orm direction [Entity=direction[/rule] ...] [--conflicts rule] [--mapping name]
 *                                            the mapping's offline sync (docs/ODATA.md, Offline): every
 *                                            entity's direction (none, down, up, both), each named
 *                                            entity's own (Entity= takes its own away), and how a both
 *                                            entity's conflicts are settled (remote, local, lastWriter,
 *                                            merge); the file written back
 *   ormtool build schema.txt model.orm      a new model from its sentences, as the verbalizer says
 *                                            them, a line each (-[ORMSentenceEditor addFromText:]);
 *                                            each line not read, with why, on standard error (1).
 *                                            An existing model is changed by apply, not rebuilt */

static void
ORMPrint(NSString *text)
{
	fputs([text UTF8String], stdout);
}

static int
ORMUsage(void)
{
	fputs("usage: ormtool verbalize [--html] model.orm\n"
	      "       ormtool check model.orm      (1 when the sample population breaks an alethic constraint)\n"
	      "       ormtool normalize model.orm [out.orm]\n"
	      "       ormtool coredata model.orm Out.xcdatamodeld [mapping name] [--validation dir/]\n"
	      "       ormtool validation model.orm dir/ [mapping name]\n"
	      "       ormtool svg [--dark] model.orm [out.svg | dir/] [diagram name]\n"
	      "       ormtool query model.orm [query name] [mapping name]\n"
	      "       ormtool import Model.xcdatamodeld [model.orm]\n"
	      "       ormtool forml model.orm [out.forml]\n"
	      "       ormtool apply model.orm changes.forml [out.orm]\n"
	      "       ormtool sync model.orm direction [Entity=direction[/rule] ...] [--conflicts rule] [--mapping name]\n"
	      "       ormtool build schema.txt model.orm\n", stderr);
	return 2;
}

static ORMEditor *
ORMOpen(NSString *path)
{
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (data == nil) {
		fprintf(stderr, "ormtool: cannot read %s\n", [path UTF8String]);
		return nil;
	}
	NSString *reason = nil;
	NSXMLDocument *document = ORMParseDocument(data, &reason);
	ORMModel *model = document != nil ? [ORMModel modelOfDocument:document reason:&reason] : nil;
	if (model == nil) {
		fprintf(stderr, "ormtool: %s: %s\n", [path UTF8String], [reason UTF8String]);
		return nil;
	}
	return [[ORMEditor alloc] initWithDocument:document undoManager:nil];
}

static int
ORMImport(NSArray<NSString *> *args)
{
	NSString *source = [args objectAtIndex:1];
	NSString *out = [args count] > 2 ? [args objectAtIndex:2] : nil;
	NSString *reason = nil;
	ORMCDModel *coreData = [ORMCDModel modelAtPath:source reason:&reason];
	if (coreData == nil) {
		fprintf(stderr, "ormtool: %s: %s\n", [source UTF8String], [reason UTF8String]);
		return 1;
	}
	ORMEditor *editor = nil;
	if (out != nil && [[NSFileManager defaultManager] fileExistsAtPath:out]) {
		editor = ORMOpen(out);
		if (editor == nil) {
			return 1;
		}
	} else {
		NSString *name = [[source lastPathComponent] stringByDeletingPathExtension];
		editor = [[ORMEditor alloc] initWithDocument:[ORMEditor newDocumentNamed:name] undoManager:nil];
	}
	NSArray *notes = nil;
	if ([[[ORMCoreDataImporter alloc] initWithEditor:editor] importCoreDataModel:coreData path:source notes:&notes reason:&reason] == nil) {
		fprintf(stderr, "ormtool: %s: %s\n", [source UTF8String], [reason UTF8String]);
		return 1;
	}
	for (NSString *note in notes) {
		fprintf(stderr, "note: %s\n", [note UTF8String]);
	}
	NSData *data = ORMDataOfDocument([editor documentForSaving]);
	if (out != nil) {
		return [data writeToFile:out atomically:YES] ? 0 : 1;
	}
	fwrite([data bytes], 1, [data length], stdout);
	return 0;
}

static int
ORMBuild(NSArray<NSString *> *args)
{
	NSString *source = [args objectAtIndex:1];
	NSString *out = [args objectAtIndex:2];
	NSError *error = nil;
	NSString *text = [NSString stringWithContentsOfFile:source encoding:NSUTF8StringEncoding error:&error];
	if (text == nil) {
		fprintf(stderr, "ormtool: cannot read %s\n", [source UTF8String]);
		return 1;
	}
	NSString *name = [[out lastPathComponent] stringByDeletingPathExtension];
	ORMEditor *editor = [[ORMEditor alloc] initWithDocument:[ORMEditor newDocumentNamed:name] undoManager:nil];
	NSArray *failures = nil;
	BOOL read = [[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures];
	for (NSString *failure in failures) {
		fprintf(stderr, "%s:%s\n", [source UTF8String], [failure UTF8String]);
	}
	if (![ORMDataOfDocument([editor documentForSaving]) writeToFile:out atomically:YES]) {
		fprintf(stderr, "ormtool: cannot write %s\n", [out UTF8String]);
		return 1;
	}
	return read ? 0 : 1;
}

/* Lines of schema text applied to the model in the file, as one change:
 * what they say made, what a "- " line says taken away. Written back
 * (or to out.orm) only when every line was read. */
static int
ORMApply(NSArray<NSString *> *args)
{
	NSString *path = [args objectAtIndex:1];
	NSString *source = [args objectAtIndex:2];
	NSString *out = [args count] > 3 ? [args objectAtIndex:3] : path;
	NSString *text = [source isEqualToString:@"-"]
		? [[NSString alloc] initWithData:[[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile]
		                        encoding:NSUTF8StringEncoding]
		: [NSString stringWithContentsOfFile:source encoding:NSUTF8StringEncoding error:NULL];
	if (text == nil) {
		fprintf(stderr, "ormtool: cannot read %s\n", [source UTF8String]);
		return 1;
	}
	ORMEditor *editor = ORMOpen(path);
	if (editor == nil) {
		return 1;
	}
	NSArray *failures = nil;
	BOOL read = [[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures];
	for (NSString *failure in failures) {
		fprintf(stderr, "%s:%s\n", [source UTF8String], [failure UTF8String]);
	}
	if (!read) {
		fprintf(stderr, "ormtool: %s left as it was\n", [out UTF8String]);
		return 1;
	}
	if (![[editor dataForSaving] writeToFile:out atomically:YES]) {
		fprintf(stderr, "ormtool: cannot write %s\n", [out UTF8String]);
		return 1;
	}
	return 0;
}

/* The value of a flag (--name value), taken out of the arguments; nil
 * when it is not there. */
static NSString *
ORMTakeFlag(NSMutableArray<NSString *> *args, NSString *flag)
{
	NSUInteger index = [args indexOfObject:flag];
	if (index == NSNotFound || index + 1 >= [args count]) {
		return nil;
	}
	NSString *value = [args objectAtIndex:index + 1];
	[args removeObjectsInRange:NSMakeRange(index, 2)];
	return value;
}

static int
ORMSync(NSArray<NSString *> *given)
{
	NSMutableArray *args = [given mutableCopy];
	NSString *mappingName = ORMTakeFlag(args, @"--mapping");
	NSString *rule = ORMTakeFlag(args, @"--conflicts");
	NSString *path = [args objectAtIndex:1];
	ORMSyncDirection direction = ORMSyncNone;
	if ([args count] < 3 || ![ORMCoreDataMapping syncDirection:&direction named:[args objectAtIndex:2]]) {
		return ORMUsage();
	}
	ORMEditor *editor = ORMOpen(path);
	if (editor == nil) {
		return 1;
	}
	ORMCoreDataMapping *mapping = nil;
	for (ORMCoreDataMapping *each in editor.model.coreDataMappings) {
		if (mappingName == nil || [each.name isEqualToString:mappingName]) {
			mapping = each;
			break;
		}
	}
	if (mapping == nil) {
		fprintf(stderr, "ormtool: %s has no Core Data mapping%s%s\n", [path UTF8String], mappingName ? " named " : "",
		        mappingName ? [mappingName UTF8String] : "");
		return 1;
	}
	ORMMappingEditor *mappings = [[ORMMappingEditor alloc] initWithEditor:editor];
	[mappings setSyncDirection:direction ofMapping:mapping.identifier];
	if (rule != nil) {
		[mappings setSyncConflicts:rule ofMapping:mapping.identifier];
	}
	/* An entity by its name in the mapping, as its source. */
	ORMCDModel *mapped = [[[ORMCoreDataMapper alloc] initWithModel:editor.model mapping:mapping] map];
	for (NSString *each in [args subarrayWithRange:NSMakeRange(3, [args count] - 3)]) {
		NSRange equals = [each rangeOfString:@"="];
		NSString *name = equals.location != NSNotFound ? [each substringToIndex:equals.location] : each;
		NSString *said = equals.location != NSNotFound ? [each substringFromIndex:NSMaxRange(equals)] : @"";
		NSArray *parts = [said componentsSeparatedByString:@"/"];
		ORMCDEntity *entity = [mapped entityNamed:name];
		ORMSyncDirection its = ORMSyncNone;
		NSString *named = [parts firstObject];
		if (entity.source == nil || ([named length] > 0 && ![ORMCoreDataMapping syncDirection:&its named:named])) {
			fprintf(stderr, "ormtool: %s: %s\n", [each UTF8String],
			        entity.source == nil ? "no entity of that name" : "no such direction");
			return 1;
		}
		[mappings setSyncDirection:[named length] > 0 ? @(its) : nil
		                 conflicts:[parts count] > 1 ? [parts objectAtIndex:1] : nil
		                  ofSource:entity.source
		                 inMapping:mapping.identifier];
	}
	if (![[editor dataForSaving] writeToFile:path atomically:YES]) {
		fprintf(stderr, "ormtool: cannot write %s\n", [path UTF8String]);
		return 1;
	}
	return 0;
}

/* The rows the plan finds in the model's sample population, as a table;
 * nil when it has none. */
static NSString *
ORMRowsText(ORMModel *model, ORMQueryPlanner *planner, ORMQueryPlan *plan)
{
	BOOL populated = NO;
	for (ORMObjectType *type in model.objectTypes) {
		populated = populated || [[type instances] count] > 0;
	}
	if (!populated || plan.entityName == nil) {
		return nil;
	}
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	ORMQueryResult *result = context != nil
		? [[[ORMQueryInterpreter alloc] initWithModel:store.managedObjectModel] executePlan:plan inContext:context
		                                                                              error:&error]
		: nil;
	if (result == nil) {
		return [NSString stringWithFormat:@"\nno rows: %@\n", [error localizedDescription]];
	}
	NSMutableArray *lines = [NSMutableArray arrayWithObject:[result.columnTitles componentsJoinedByString:@" | "]];
	for (NSArray *row in result.rows) {
		NSMutableArray *cells = [NSMutableArray array];
		for (id value in row) {
			/* An object identified by several values: "BSc, UQ". */
			id shown = value;
			if ([value isKindOfClass:[NSArray class]]) {
				NSMutableArray *parts = [NSMutableArray array];
				for (id part in value) {
					[parts addObject:part == [NSNull null] ? @"-" : [part description]];
				}
				shown = [parts componentsJoinedByString:@", "];
			}
			[cells addObject:shown == [NSNull null] ? @"-" : [shown description]];
		}
		[lines addObject:[cells componentsJoinedByString:@" | "]];
	}
	return [NSString stringWithFormat:@"\nsample population: %lu %@\n%@\n", (unsigned long)[result.rows count],
	                                  [result.rows count] == 1 ? @"row" : @"rows", [lines componentsJoinedByString:@"\n"]];
}

int
main(int argc, const char *argv[])
{
	@autoreleasepool {
		NSMutableArray *args = [NSMutableArray array];
		for (int i = 1; i < argc; i++) {
			[args addObject:[NSString stringWithUTF8String:argv[i]]];
		}
		if ([args count] < 2) {
			return ORMUsage();
		}
		NSString *command = [args objectAtIndex:0];
		BOOL html = [args containsObject:@"--html"];
		[args removeObject:@"--html"];
		BOOL dark = [args containsObject:@"--dark"];
		[args removeObject:@"--dark"];
		/* coredata's validation code written there, not where the mapping
		 * keeps it: a build's output. */
		NSString *validationDirectory = nil;
		NSUInteger flag = [args indexOfObject:@"--validation"];
		if (flag != NSNotFound && flag + 1 < [args count]) {
			validationDirectory = [args objectAtIndex:flag + 1];
			[args removeObjectsInRange:NSMakeRange(flag, 2)];
		}
		if ([command isEqualToString:@"import"]) {
			return ORMImport(args);
		}
		if ([command isEqualToString:@"build"]) {
			return [args count] >= 3 ? ORMBuild(args) : ORMUsage();
		}
		if ([command isEqualToString:@"apply"]) {
			return [args count] >= 3 ? ORMApply(args) : ORMUsage();
		}
		if ([command isEqualToString:@"sync"]) {
			return [args count] >= 3 ? ORMSync(args) : ORMUsage();
		}
		ORMEditor *editor = ORMOpen([args objectAtIndex:1]);
		if (editor == nil) {
			return 1;
		}
		ORMModel *model = editor.model;
		if ([command isEqualToString:@"forml"]) {
			NSString *text = [[[ORMSchemaText alloc] initWithEditor:editor] textFromFile:[args objectAtIndex:1]];
			if ([args count] > 2) {
				NSError *error = nil;
				if (![text writeToFile:[args objectAtIndex:2] atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
					fprintf(stderr, "ormtool: cannot write %s\n", [[args objectAtIndex:2] UTF8String]);
					return 1;
				}
				return 0;
			}
			ORMPrint(text);
			return 0;
		}
		if ([command isEqualToString:@"verbalize"]) {
			NSArray *sentences = [[[ORMVerbalizer alloc] initWithModel:model] sentencesForModel];
			ORMPrint(html ? [ORMVerbalizer HTMLOfSentences:sentences title:model.name]
			              : [ORMVerbalizer plainTextOfSentences:sentences]);
			return 0;
		}
		if ([command isEqualToString:@"check"]) {
			NSUInteger shapes = 0;
			for (ORMDiagram *diagram in model.diagrams) {
				shapes += [[diagram allShapes] count];
			}
			ORMPrint([NSString stringWithFormat:@"%@: %lu object types, %lu fact types, %lu constraints, "
			                                    @"%lu diagrams, %lu shapes\n",
			          model.name, (unsigned long)[[model visibleObjectTypes] count],
			          (unsigned long)[[model ordinaryFactTypes] count], (unsigned long)[model.constraints count],
			          (unsigned long)[model.diagrams count], (unsigned long)shapes]);
			/* The sample population against the constraints and the rules. */
			ORMPopulationChecker *checker = [[ORMPopulationChecker alloc] initWithModel:model];
			NSUInteger broken = 0;
			for (ORMPopulationViolation *violation in [checker violations]) {
				BOOL deontic = violation.rule != nil ? violation.rule.isDeontic
				                                     : violation.constraint.modality == ORMDeontic;
				broken += deontic ? 0 : 1;
				ORMPrint([NSString stringWithFormat:@"%@: %@\n", deontic ? @"breaks (deontic)" : @"breaks",
				                                    violation.text]);
			}
			for (NSString *note in [checker unchecked]) {
				ORMPrint([NSString stringWithFormat:@"not checked: %@\n", note]);
			}
			return broken > 0 ? 1 : 0;
		}
		if ([command isEqualToString:@"normalize"]) {
			[editor group:@"Normalize" with:^{
			}];
			NSData *data = ORMDataOfDocument(editor.document);
			if ([args count] > 2) {
				return [data writeToFile:[args objectAtIndex:2] atomically:YES] ? 0 : 1;
			}
			fwrite([data bytes], 1, [data length], stdout);
			return 0;
		}
		if ([command isEqualToString:@"coredata"] && [args count] >= 3) {
			/* The named mapping the model keeps, or the defaults. */
			ORMCoreDataMapping *mapping = nil;
			for (ORMCoreDataMapping *each in editor.model.coreDataMappings) {
				if ([args count] < 4 || [each.name isEqualToString:[args objectAtIndex:3]]) {
					mapping = each;
					break;
				}
			}
			ORMCoreDataMapper *mapper = [[ORMCoreDataMapper alloc] initWithModel:model mapping:mapping];
			ORMCDModel *mapped = [mapper map];
			NSError *error = nil;
			if (![mapped writeToPackage:[args objectAtIndex:2] error:&error]) {
				fprintf(stderr, "ormtool: %s\n", [[error localizedDescription] UTF8String]);
				return 1;
			}
			ORMPrint([NSString stringWithFormat:@"%lu entities\n", (unsigned long)[mapped.entities count]]);
			NSString *validation = validationDirectory ?: [mapping resolvedValidationPathRelativeTo:[args objectAtIndex:1]];
			if (validation != nil) {
				NSString *name = mapping.name ?: [[[args objectAtIndex:1] lastPathComponent] stringByDeletingPathExtension];
				ORMValidationGenerator *generator = [[ORMValidationGenerator alloc]
					initWithModel:model coreData:mapped notes:mapper.notes name:name];
				if (![generator writeToDirectory:validation error:&error]) {
					fprintf(stderr, "ormtool: %s\n", [[error localizedDescription] UTF8String]);
					return 1;
				}
				ORMPrint([NSString stringWithFormat:@"%lu constraints checked in %@\n",
				                                    (unsigned long)generator.ruleCount, validation]);
				for (NSString *note in generator.notes) {
					ORMPrint([NSString stringWithFormat:@"not checked: %@\n", note]);
				}
			}
			for (ORMMappingNote *note in mapper.notes) {
				NSString *kind = note.kind == ORMMappingAbsorbed ? @"absorbed"
					: note.kind == ORMMappingUnenforced ? @"unenforced" : @"note";
				ORMPrint([NSString stringWithFormat:@"%@: %@\n", kind, note.text]);
			}
			return 0;
		}
		if ([command isEqualToString:@"validation"] && [args count] >= 3) {
			ORMCoreDataMapping *mapping = nil;
			for (ORMCoreDataMapping *each in editor.model.coreDataMappings) {
				if ([args count] < 4 || [each.name isEqualToString:[args objectAtIndex:3]]) {
					mapping = each;
					break;
				}
			}
			NSString *name = mapping.name ?: [[[args objectAtIndex:1] lastPathComponent] stringByDeletingPathExtension];
			ORMValidationGenerator *generator = [[ORMValidationGenerator alloc] initWithModel:model mapping:mapping
			                                                                             name:name];
			NSError *error = nil;
			if (![generator writeToDirectory:[args objectAtIndex:2] error:&error]) {
				fprintf(stderr, "ormtool: %s\n", [[error localizedDescription] UTF8String]);
				return 1;
			}
			ORMPrint([NSString stringWithFormat:@"%lu constraints checked\n", (unsigned long)generator.ruleCount]);
			for (NSString *note in generator.notes) {
				ORMPrint([NSString stringWithFormat:@"not checked: %@\n", note]);
			}
			return 0;
		}
		if ([command isEqualToString:@"query"]) {
			ORMCoreDataMapping *mapping = nil;
			for (ORMCoreDataMapping *each in editor.model.coreDataMappings) {
				if ([args count] < 4 || [each.name isEqualToString:[args objectAtIndex:3]]) {
					mapping = each;
					break;
				}
			}
			NSArray *queries = [ORMQuery queriesInModel:model];
			BOOL found = NO;
			for (ORMQuery *query in queries) {
				if ([args count] > 2 && ![query.name isEqualToString:[args objectAtIndex:2]]) {
					continue;
				}
				found = YES;
				ORMPrint([NSString stringWithFormat:@"%@\n\n%@\n", query.name, [query outlineText]]);
				ORMPrint([ORMVerbalizer plainTextOfSentences:[[[ORMVerbalizer alloc] initWithModel:model]
				                                                 sentencesForQuery:query]]);
				NSError *refused = nil;
				ORMQueryOData *odata = [ORMQueryOData requestForQuery:query model:model mapping:mapping error:&refused];
				ORMPrint([NSString stringWithFormat:@"\n%@", odata != nil ? [odata requestText]
				                                                     : [NSString stringWithFormat:@"no request: %@\n",
				                                                                                  [refused localizedDescription]]]);
				for (NSString *note in odata.notes) {
					ORMPrint([NSString stringWithFormat:@"note: %@\n", note]);
				}
				ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:mapping];
				ORMQueryPlan *plan = [planner planForQuery:query];
				ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc]
					initWithModel:[planner.coreData managedObjectModel]];
				NSString *program = plan.entityName != nil ? [interpreter programForPlan:plan error:NULL] : nil;
				ORMPrint([NSString stringWithFormat:@"\n%@\n\n%@\n", [plan text], program ?: @""]);
				ORMPrint([ORMRowsText(model, planner, plan) ?: @"" stringByAppendingString:@"\n"]);
			}
			if (!found) {
				fprintf(stderr, "ormtool: %s\n", [args count] > 2 ? "no query of that name" : "the model has no queries");
				return 1;
			}
			return 0;
		}
		if ([command isEqualToString:@"svg"]) {
			NSString *out = [args count] > 2 ? [args objectAtIndex:2] : nil;
			NSString *named = [args count] > 3 ? [args objectAtIndex:3] : nil;
			BOOL isDirectory = NO;
			BOOL toDirectory = [out hasSuffix:@"/"]
				|| ([[NSFileManager defaultManager] fileExistsAtPath:out ?: @"" isDirectory:&isDirectory] && isDirectory);
			NSMutableArray *diagrams = [NSMutableArray array];
			for (ORMDiagram *diagram in model.diagrams) {
				if (named == nil || [diagram.name isEqualToString:named]) {
					[diagrams addObject:diagram];
				}
			}
			if ([diagrams count] == 0) {
				fprintf(stderr, "ormtool: %s\n", named != nil ? [[NSString stringWithFormat:@"no diagram named %@", named] UTF8String]
				                                                 : "the model has no diagrams");
				return 1;
			}
			if (!toDirectory) {
				NSString *svg = ORMSVGOfDiagram([diagrams firstObject], dark);
				if (out == nil || [out isEqualToString:@"-"]) {
					ORMPrint(svg);
					return 0;
				}
				return [svg writeToFile:out atomically:YES encoding:NSUTF8StringEncoding error:NULL] ? 0 : 1;
			}
			[[NSFileManager defaultManager] createDirectoryAtPath:out withIntermediateDirectories:YES attributes:nil
			                                                error:NULL];
			NSMutableSet *used = [NSMutableSet set];
			for (ORMDiagram *diagram in diagrams) {
				/* A file a diagram: unnamed ones, and ones that share a name,
				 * numbered. */
				NSString *base = [[diagram.name ?: @"" stringByReplacingOccurrencesOfString:@"/" withString:@"-"]
					stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
				base = [base length] > 0 ? base : @"Diagram";
				NSString *stem = base;
				for (NSUInteger n = 2; [used containsObject:[stem lowercaseString]]; n++) {
					stem = [NSString stringWithFormat:@"%@ %lu", base, (unsigned long)n];
				}
				[used addObject:[stem lowercaseString]];
				NSString *name = [stem stringByAppendingString:@".svg"];
				NSString *path = [out stringByAppendingPathComponent:name];
				if (![ORMSVGOfDiagram(diagram, dark) writeToFile:path atomically:YES encoding:NSUTF8StringEncoding
				                                           error:NULL]) {
					fprintf(stderr, "ormtool: cannot write %s\n", [path UTF8String]);
					return 1;
				}
				ORMPrint([path stringByAppendingString:@"\n"]);
			}
			return 0;
		}
		return ORMUsage();
	}
}
