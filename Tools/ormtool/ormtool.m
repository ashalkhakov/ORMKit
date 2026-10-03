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
 *                                            the model mapped to Core Data, with the mapping's report */

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
	      "       ormtool coredata model.orm Out.xcdatamodeld [mapping name]\n", stderr);
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
			for (ORMMappingNote *note in mapper.notes) {
				NSString *kind = note.kind == ORMMappingAbsorbed ? @"absorbed"
					: note.kind == ORMMappingUnenforced ? @"unenforced" : @"note";
				ORMPrint([NSString stringWithFormat:@"%@: %@\n", kind, note.text]);
			}
			return 0;
		}
		return ORMUsage();
	}
}
