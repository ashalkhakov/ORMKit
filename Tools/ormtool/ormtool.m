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
 *   ormtool check model.orm                  what the model holds, and whether it reads
 *   ormtool normalize model.orm [out.orm]    NORMA's derived data brought up to date
 *   ormtool coredata model.orm Out.xcdatamodeld [mapping name]
 *                                            the model mapped to Core Data, with the mapping's report;
 *                                            the validation code too, where the mapping keeps it
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
 *                                            ODataKit makes of the mapping, the plan, and how the
 *                                            interpreter runs it against a Core Data store
 *   ormtool import Model.xcdatamodeld [model.orm]
 *                                            the Core Data model in ORM: added to the .orm when it
 *                                            exists, else a new model, written there or to standard
 *                                            output, with what ORM cannot say on standard error */

static void
ORMPrint(NSString *text)
{
	fputs([text UTF8String], stdout);
}

static int
ORMUsage(void)
{
	fputs("usage: ormtool verbalize [--html] model.orm\n"
	      "       ormtool check model.orm\n"
	      "       ormtool normalize model.orm [out.orm]\n"
	      "       ormtool coredata model.orm Out.xcdatamodeld [mapping name]\n"
	      "       ormtool validation model.orm dir/ [mapping name]\n"
	      "       ormtool svg [--dark] model.orm [out.svg | dir/] [diagram name]\n"
	      "       ormtool query model.orm [query name] [mapping name]\n"
	      "       ormtool import Model.xcdatamodeld [model.orm]\n", stderr);
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
		if ([command isEqualToString:@"import"]) {
			return ORMImport(args);
		}
		ORMEditor *editor = ORMOpen([args objectAtIndex:1]);
		if (editor == nil) {
			return 1;
		}
		ORMModel *model = editor.model;
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
			return 0;
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
			for (ORMCoreDataMapping *each in [ORMCoreDataMapping mappingsOfDocument:editor.document]) {
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
			NSString *validation = [mapping resolvedValidationPathRelativeTo:[args objectAtIndex:1]];
			if (validation != nil) {
				ORMValidationGenerator *generator = [[ORMValidationGenerator alloc]
					initWithModel:model coreData:mapped notes:mapper.notes name:mapping.name];
				if (![generator writeToDirectory:validation error:&error]) {
					fprintf(stderr, "ormtool: %s\n", [[error localizedDescription] UTF8String]);
					return 1;
				}
				ORMPrint([NSString stringWithFormat:@"%lu constraints checked in %@\n",
				                                    (unsigned long)generator.ruleCount, validation]);
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
			for (ORMCoreDataMapping *each in [ORMCoreDataMapping mappingsOfDocument:editor.document]) {
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
			for (ORMCoreDataMapping *each in [ORMCoreDataMapping mappingsOfDocument:editor.document]) {
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
				ORMPrint(@"\n");
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
